import CoachLLM
import Core
import Foundation
import NutritionKit
import Persistence
import PlanKit

/// One presentation-ready plan option: deterministic engine candidate plus
/// LLM-written (or fallback) copy.
public struct PlanBuilderOption: Sendable, Equatable, Identifiable {
    public let candidate: CandidatePlan
    public let copy: PlanOptionCardCopy

    public var id: String { candidate.id }

    public init(candidate: CandidatePlan, copy: PlanOptionCardCopy) {
        self.candidate = candidate
        self.copy = copy
    }
}

/// Orchestrates the plan-builder flow: candidates -> LLM card copy -> session persistence.
@MainActor
@Observable
public final class PlanBuilderService {
    public private(set) var options: [PlanBuilderOption] = []
    public private(set) var isGenerating = false
    public private(set) var generationMessage: String?

    private let persistence: PersistenceStore
    private let provider: (any CoachLLMProvider)?

    public init(persistence: PersistenceStore, provider: (any CoachLLMProvider)?) {
        self.persistence = persistence
        self.provider = provider
    }

    /// Prefills an interview from what Helm already knows.
    public func makePrefilledInterview() -> PlanBuilderInterview {
        var interview = PlanBuilderInterview()
        if let settings = try? persistence.trainingPlan.load() {
            interview.sessionDurationMinutes = settings.sessionDurationMinutes
            interview.daysPerWeek = settings.daysPerWeek
            interview.experienceRaw = settings.experienceRaw
            interview.emphasis = settings.phaseGoal.emphasis
        }
        if let profile = BodyProfileStore(metadata: persistence.appMetadata).load(),
           let tdee = BodyProfileTDEE.seedTDEEKcal(profile: profile) {
            interview.confirmedMaintenanceKcal = (tdee * 10).rounded() / 10
            interview.usesComputedEstimate = true
        }
        return interview
    }

    public func loadResumableSession() -> StoredPlanBuilderSession? {
        try? persistence.planBuilderSession.load()
    }

    /// Encodes generated options for session persistence.
    public static func encodeOptions(_ options: [PlanBuilderOption]) throws -> [StoredPlanBuilderOption] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try options.map { option in
            StoredPlanBuilderOption(
                encodedCandidate: String(data: try encoder.encode(option.candidate), encoding: .utf8) ?? "",
                encodedCopy: String(data: try encoder.encode(option.copy), encoding: .utf8) ?? ""
            )
        }
    }

    /// Decodes persisted options back into presentation-ready form. Malformed
    /// entries are skipped rather than failing the whole restore.
    public static func decodeOptions(_ stored: [StoredPlanBuilderOption]) -> [PlanBuilderOption] {
        let decoder = JSONDecoder()
        return stored.compactMap { entry in
            guard let candidateData = entry.encodedCandidate.data(using: .utf8),
                  let copyData = entry.encodedCopy.data(using: .utf8),
                  let candidate = try? decoder.decode(CandidatePlan.self, from: candidateData),
                  let copy = try? decoder.decode(PlanOptionCardCopy.self, from: copyData)
            else { return nil }
            return PlanBuilderOption(candidate: candidate, copy: copy)
        }
    }

    public func saveSession(_ session: StoredPlanBuilderSession) {
        do {
            try persistence.planBuilderSession.save(session)
        } catch {
            generationMessage = error.localizedDescription
        }
    }

    /// Persists interview answers plus generated options so a relaunch resumes at the cards.
    public func saveResumableState(interview: PlanBuilderInterview, options: [PlanBuilderOption]) {
        guard let encoded = try? Self.encodeOptions(options) else { return }
        saveSession(
            StoredPlanBuilderSession(
                interview: interview,
                options: encoded
            )
        )
    }

    /// Restores a previous generation pass if one exists.
    public func restoredOptions() -> [PlanBuilderOption]? {
        guard let session = loadResumableSession(), !session.options.isEmpty else { return nil }
        let decoded = Self.decodeOptions(session.options)
        return decoded.isEmpty ? nil : decoded
    }

    /// Generates candidates deterministically, then asks Coach for grounded
    /// per-card copy. Falls back to engine-derived copy when unavailable.
    public func generateOptions(for interview: PlanBuilderInterview) async {
        isGenerating = true
        defer { isGenerating = false }

        let interpreted = PlanBuilderDiscussionInterpreter.applying(interview.discussionNote, to: interview)
        let preferredTemplate = PlanBuilderDiscussionInterpreter.interpret(interview.discussionNote)
            .preferredTemplateRaw
        let candidates = CandidatePlanGenerator.generate(
            interview: interpreted,
            experience: CandidatePlanGenerator.experience(of: interpreted),
            preferredTemplateRaw: preferredTemplate
        )

        var copies: [String: PlanOptionCardCopy] = [:]
        if let provider {
            do {
                let payload = try await requestCards(candidates: candidates, interview: interpreted)
                for card in payload.cards {
                    copies[card.candidateID] = card
                }
            } catch {
                generationMessage = "Coach copy unavailable; showing engine summaries."
            }
        } else {
            generationMessage = "No coach key set; showing engine summaries."
        }

        options = candidates.map { candidate in
            PlanBuilderOption(
                candidate: candidate,
                copy: copies[candidate.id] ?? Self.fallbackCopy(for: candidate)
            )
        }
    }

    public struct ExampleWorkoutPreview: Sendable, Equatable {
        public let dayKind: TrainingDayKind
        public let exercises: [ExampleWorkoutExercise]
    }

    public struct ExampleWorkoutExercise: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let sets: Int
        public let patternLabel: String
    }

    /// Dry-run first session for a candidate. Does not write planned workouts.
    public func previewExampleWorkout(for candidate: CandidatePlan) -> ExampleWorkoutPreview {
        let dayKind = CandidatePlanGenerator.exampleDayKind(for: candidate)
        let budget = SessionDurationBudget.from(minutes: candidate.sessionDurationMinutes)
        let template = ProgramTemplate(rawValue: candidate.programTemplateRaw) ?? .ppl
        let rows = (try? persistence.exercises.fetchCatalogRows()) ?? []
        let catalog = PrescriptionCatalogBuilder.build(from: rows)
        let lines = PlanKit.exampleWorkout(
            dayKind: dayKind,
            budget: budget,
            template: template,
            catalog: catalog
        )
        let names = (try? persistence.exercises.displayNames(for: lines.map(\.exerciseID))) ?? [:]
        let exercises = lines.map { line in
            ExampleWorkoutExercise(
                id: line.exerciseID,
                name: names[line.exerciseID] ?? line.exerciseID,
                sets: line.targetSets,
                patternLabel: line.pattern.rawValue
            )
        }
        return ExampleWorkoutPreview(dayKind: dayKind, exercises: exercises)
    }

    /// Computes updated training-plan settings from the chosen option.
    public func makeUpdatedSettings(
        option: PlanBuilderOption,
        interview: PlanBuilderInterview
    ) throws -> StoredTrainingPlanSettings {
        guard let settings = try? persistence.trainingPlan.load() else {
            throw PlanBuilderError.settingsUnavailable
        }
        var next = settings
        next.programTemplateRaw = option.candidate.programTemplateRaw
        next.daysPerWeek = option.candidate.daysPerWeek
        next.dayKindRotationRaw = option.candidate.dayKindRotation.map(\.rawValue)
        next.sessionDurationMinutes = interview.sessionDurationMinutes
        next.experienceRaw = interview.experienceRaw
        // Interview emphasis replaces any prior value; the maintenance note is
        // refreshed (not appended) so repeated commits never duplicate it.
        let notes = [interview.emphasis, Self.maintenanceNote(interview.confirmedMaintenanceKcal)]
            .compactMap(\.self)
            .joined(separator: ", ")
        next.phaseGoal = PhaseGoal(
            phase: next.phaseGoal.phase,
            weeklyRateKg: next.phaseGoal.weeklyRateKg,
            targetMass: next.phaseGoal.targetMass,
            emphasis: notes.isEmpty ? nil : notes
        )
        syncProgressionGoal(interview.progressionGoal, into: &next)
        return next
    }

    static func maintenanceNote(_ kcal: Double?) -> String? {
        guard let kcal else { return nil }
        return "maintenance ~\(Int(kcal)) kcal/day"
    }

    /// Stores the progression goal as a structured preference line in MemoryProfile
    /// so coach chat and future plan builds can read it back.
    private func syncProgressionGoal(
        _ goal: PlanBuilderInterview.ProgressionGoal,
        into settings: inout StoredTrainingPlanSettings
    ) {
        do {
            var profile = try persistence.memoryProfile.load()
            let parsed = MethodologyPreferences.parse(from: profile.preferences)
            var freeform = parsed.freeform
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { line in
                    !line.trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                        .hasPrefix("\(Self.goalKey)=")
                }
            freeform.append("\(Self.goalKey)=\(goal.rawValue)")
            profile.preferences = parsed.preferences.merge(into: freeform.joined(separator: "\n"))
            try persistence.memoryProfile.save(profile)
        } catch {
            // Goal persistence is best-effort; the plan itself still commits.
        }
    }

    static let goalKey = "progressionGoal"

    public func clearSession() {
        try? persistence.planBuilderSession.clear()
    }

    static func fallbackCopy(for candidate: CandidatePlan) -> PlanOptionCardCopy {
        let trainedMuscles = candidate.weeklyPeakSetsByMuscle.keys.count
        let totalSets = candidate.weeklyPeakSetsByMuscle.values.reduce(0, +)
        let outcome = "\(candidate.daysPerWeek) sessions/week at \(totalSets) peak weekly sets across \(trainedMuscles) muscles."
        return PlanOptionCardCopy(
            candidateID: candidate.id,
            outcome: outcome,
            benefits: Array(candidate.leverNotes.prefix(2)),
            challenges: []
        )
    }

    private func requestCards(
        candidates: [CandidatePlan],
        interview: PlanBuilderInterview
    ) async throws -> PlanOptionCardsPayload {
        guard let provider else {
            throw PlanBuilderError.providerUnavailable
        }
        let facts = candidates.map { candidate -> String in
            let sets = candidate.weeklyPeakSetsByMuscle
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue): \($0.value)" }
                .joined(separator: ", ")
            let freq = candidate.frequencyByMuscle
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.rawValue): \($0.value)x/week" }
                .joined(separator: ", ")
            return """
            {"candidateID":"\(candidate.id)","headline":"\(candidate.headline)","daysPerWeek":\(candidate.daysPerWeek), \
            "sessionMinutes":\(candidate.sessionDurationMinutes),"weeklyPeakHardSets":{\(sets)}, \
            "frequency":{\(freq)},"deloadCadenceWeeks":\(candidate.deloadCadenceWeeks), \
            "availabilityFit":\(String(format: "%.2f", candidate.availabilityFitScore))}
            """
        }.joined(separator: ",\n")

        let userMessage = """
        Athlete goal: \(interview.progressionGoal.rawValue) (\(interview.progressionGoal.label)). \
        Experience: \(interview.experienceRaw). \
        Available days: \(interview.daysPerWeek)/week. Session length: \(interview.sessionDurationMinutes) minutes.\
        \(interview.emphasis.map { " Stated emphasis: \($0)." } ?? "")\
        \(interview.discussionNote.map { " Athlete asked for a different option: \($0)." } ?? "")
        Candidates:
        [
        \(facts)
        ]
        Produce one card per candidateID.
        """
        return try await provider.generatePlanOptionCards(
            systemInstructions: CoachSystemPrompt.planOptionCardsV1,
            userMessage: userMessage
        )
    }
}

public enum PlanBuilderError: Error, Sendable {
    case providerUnavailable
    case settingsUnavailable
}
