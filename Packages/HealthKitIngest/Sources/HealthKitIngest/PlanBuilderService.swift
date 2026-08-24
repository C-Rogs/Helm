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
    private let provider: GeminiProvider?

    public init(persistence: PersistenceStore, provider: GeminiProvider?) {
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

    public func saveSession(_ session: StoredPlanBuilderSession) {
        do {
            try persistence.planBuilderSession.save(session)
        } catch {
            generationMessage = error.localizedDescription
        }
    }

    /// Generates candidates deterministically, then asks Gemini for grounded
    /// per-card copy. Falls back to engine-derived copy when unavailable.
    public func generateOptions(for interview: PlanBuilderInterview) async {
        isGenerating = true
        defer { isGenerating = false }

        let candidates = CandidatePlanGenerator.generate(
            interview: interview,
            experience: CandidatePlanGenerator.experience(of: interview)
        )

        var copies: [String: PlanOptionCardCopy] = [:]
        if let provider {
            do {
                let payload = try await requestCards(candidates: candidates, interview: interview)
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
            var lines = parsed.freeform
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
                .filter { !$0.hasPrefix("\(Self.goalKey)=") }
            lines.append("\(Self.goalKey)=\(goal.rawValue)")
            profile.preferences = lines.joined(separator: "\n")
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
        \(interview.emphasis.map { " Stated emphasis: \($0)." } ?? "")
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
