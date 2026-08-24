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

        let experienceRaw = (try? persistence.trainingPlan.load())?.experienceRaw
        let experience = experienceRaw.flatMap(TrainingExperience.init(rawValue:)) ?? .intermediate

        let candidates = CandidatePlanGenerator.generate(
            interview: interview,
            experience: experience
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
        if let kcal = interview.confirmedMaintenanceKcal {
            // Maintenance confirmation is recorded as an emphasis note;
            // nutrition targets stay owned by NutritionKit adaptive TDEE.
            let note = "maintenance ~\(Int(kcal)) kcal/day"
            next.phaseGoal = PhaseGoal(
                phase: next.phaseGoal.phase,
                weeklyRateKg: next.phaseGoal.weeklyRateKg,
                targetMass: next.phaseGoal.targetMass,
                emphasis: [next.phaseGoal.emphasis, note].compactMap(\.self).joined(separator: ", ")
            )
        }
        return next
    }

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
        Athlete goal: \(interview.progressionGoal.rawValue). \
        Available days: \(interview.daysPerWeek)/week. Session length: \(interview.sessionDurationMinutes) minutes.
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
