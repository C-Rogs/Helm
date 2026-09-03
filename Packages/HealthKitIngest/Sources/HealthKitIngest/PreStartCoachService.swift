import CoachLLM
import Core
import Foundation
import Persistence
import PlanKit

public struct PreStartCoachIntro: Sendable, Equatable {
    public let text: String
    public let isEngineOnly: Bool

    public init(text: String, isEngineOnly: Bool) {
        self.text = text
        self.isEngineOnly = isEngineOnly
    }
}

public struct PreStartCoachService: Sendable {
    private let persistence: PersistenceStore
    private let inSessionCoach: InSessionCoachService

    public init(persistence: PersistenceStore) {
        self.persistence = persistence
        inSessionCoach = InSessionCoachService(persistence: persistence)
    }

    public func engineIntro(for brief: SessionDesignBrief, summary: PrescribedSessionSummary) -> PreStartCoachIntro {
        let exerciseNames = summary.exercises.map(\.displayName).joined(separator: ", ")
        let rationale = brief.rationale.joined(separator: " ")
        let text = "\(brief.title): \(brief.summary). \(rationale) Exercises: \(exerciseNames). Ask about volume, swaps, or readiness before you start."
        return PreStartCoachIntro(text: text, isEngineOnly: true)
    }

    public func generateIntro(
        brief: SessionDesignBrief,
        summary: PrescribedSessionSummary,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        context: CoachContextDays
    ) async throws -> PreStartCoachIntro {
        let availability = await provider.availability()
        guard availability.isAvailable else {
            return engineIntro(for: brief, summary: summary)
        }

        let prompt = """
        Introduce today's prescribed session in chat-length prose (same coach voice as main chat).
        Title: \(brief.title)
        Summary: \(brief.summary)
        Rationale: \(brief.rationale.joined(separator: "; "))
        Exercises: \(summary.exercises.map(\.displayName).joined(separator: ", "))
        Invite the athlete to ask about volume, swaps, readiness, or how today's session fits their training emphasis before starting.
        If Training Plan Snapshot includes emphasis, explain briefly how it could fit today's \(brief.splitKind.label) session when relevant; do not rewrite the engine prescription unless asked.
        \(warmUpGuidance(from: profile))
        """

        let budget = TokenBudget.maxInputTokens(for: .gemini)
        let built = ContextBuilder.build(
            profile: profile,
            days: context,
            budget: budget,
            turn: .initial
        )

        let stream = try await provider.respond(
            systemInstructions: built.systemInstructions,
            contextBlock: built.contextBlock,
            userMessage: prompt,
            thread: .empty,
            freshnessSuffix: built.freshnessSuffix
        )

        var assembled = ""
        for try await chunk in stream {
            assembled += chunk
        }
        let trimmed = assembled.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CoachStructuredOutputError.emptyResponse
        }
        return PreStartCoachIntro(text: trimmed, isEngineOnly: false)
    }

    private func warmUpGuidance(from profile: MemoryProfile) -> String {
        let today = HelmDay.day(for: Date(), calendar: .current)
        let signals = StandingConstraintNotes.evaluate(profile.standingConstraints, on: today)
        guard signals.encourageWarmUpStretch else { return "" }
        let joints = signals.activeJoints.sorted()
        if !joints.isEmpty {
            let labels = joints.map { JointRecoveryCatalog.normalize($0) }.joined(separator: ", ")
            let patterns = StandingConstraintPatternPolicy.excludedPatterns(forActiveJoints: signals.activeJoints)
            if patterns.isEmpty {
                return "Standing Constraints show an active recovery window (\(labels)): for the session intro only, encourage a thorough warm-up and stretch. Do not invent load reductions for lifts outside soft-paused patterns."
            }
            let patternLabels = patterns.map(\.rawValue).sorted().joined(separator: ", ")
            return "Standing Constraints show an active recovery window (\(labels)): soft-paused patterns are \(patternLabels). Mention those pattern pauses only. Do not invent load cuts for other lifts (e.g. face pulls when only vertical press is paused)."
        }
        return "Standing Constraints suggest encouraging a thorough warm-up and stretch for today's session. Do not invent per-lift load stories from constraints alone."
    }

    public func proposeAdjustment(
        userMessage: String,
        prescription: SessionPrescription,
        excludedExerciseIDs: Set<String>,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        context: CoachContextDays,
        thread: CoachThreadState = .empty
    ) async throws -> CoachSessionProposal {
        let snapshot = PrescriptionCoachSnapshotBuilder.snapshot(from: prescription)
        return try await inSessionCoach.proposeAdjustment(
            userMessage: userMessage,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs,
            provider: provider,
            profile: profile,
            context: context,
            thread: thread
        )
    }

    public func applyProposal(
        _ proposal: CoachSessionProposal,
        prescription: SessionPrescription,
        excludedExerciseIDs: Set<String>,
        day: HelmDay
    ) async throws -> (prescription: SessionPrescription, persist: HelmActionResult) {
        try await applyAdjustmentToPrescription(
            proposal: proposal,
            prescription: prescription,
            excludedExerciseIDs: excludedExerciseIDs,
            day: day
        )
    }

    public func applyAdjustmentToPrescription(
        proposal: CoachSessionProposal,
        prescription: SessionPrescription,
        excludedExerciseIDs: Set<String>,
        day: HelmDay
    ) async throws -> (prescription: SessionPrescription, persist: HelmActionResult) {
        let snapshot = PrescriptionCoachSnapshotBuilder.snapshot(from: prescription)
        let stampedPayload = LoadAdjustmentIntentClassifier.stamp(
            payload: proposal.payload,
            userMessage: nil
        )
        let sessionExerciseIDs = Set(snapshot.session.exercises.map(\.exerciseID))
        let orderedSessionExerciseIDs = snapshot.session.exercises
            .sorted { $0.displayOrder < $1.displayOrder }
            .map(\.exerciseID)
        let displayNames = try persistence.exercises.displayNames(for: Array(sessionExerciseIDs))
        let rows = try persistence.exercises.fetchCatalogRows()
        let familiarExerciseIDs = PrescriptionHistoryBuilder.familiarExerciseIDs(
            from: try PrescriptionHistoryBuilder.history(from: persistence, endingAt: day)
        )
        let catalog = PrescriptionCatalogBuilder.build(
            from: rows,
            familiarExerciseIDs: familiarExerciseIDs
        )
        let normalized = try SessionExerciseIDResolver.normalize(
            payload: stampedPayload,
            sessionExerciseIDs: sessionExerciseIDs,
            exerciseDisplayNames: displayNames,
            persistence: persistence,
            excludedExerciseIDs: excludedExerciseIDs,
            familiarExerciseIDs: familiarExerciseIDs,
            orderedSessionExerciseIDs: orderedSessionExerciseIDs
        )
        guard normalized.unresolvedExerciseIDs.isEmpty else {
            throw InSessionCoachError.noApplicableChange
        }

        let adjustment = SessionAdjustmentMapper.prescriptionAdjustment(from: normalized.payload)
        guard !adjustment.operations.isEmpty else {
            throw InSessionCoachError.noApplicableChange
        }

        let result = PlanKit.apply(
            adjustment: adjustment,
            to: prescription,
            excluding: excludedExerciseIDs,
            catalog: catalog,
            familiarExerciseIDs: familiarExerciseIDs
        )

        switch result {
        case .rejected:
            throw InSessionCoachError.noApplicableChange
        case .applied(let adjusted):
            let titled = SessionPrescription(
                id: adjusted.id,
                helmDay: adjusted.helmDay,
                title: prescription.title,
                exercises: adjusted.exercises
            )
            let history = try PrescriptionHistoryBuilder.history(from: persistence, endingAt: day)
            let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map {
                ($0.exerciseID, $0.muscleMap)
            })
            let settings = try persistence.trainingPlan.load()
            let fingerprint = PrescriptionHistoryBuilder.historyFingerprint(
                history,
                through: day,
                muscleMaps: muscleMaps,
                dayKindRotation: TrainingPlanShape.dayKindRotation(from: settings)
            )
            let persist = try await HelmActionExecutor(persistence: persistence).run(
                .persistAdjustedPrescription(HelmAdjustedPrescriptionCommand(
                    prescription: titled,
                    day: day,
                    historyFingerprint: fingerprint
                ))
            )
            return (titled, persist)
        }
    }
}
