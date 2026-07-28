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
        contextDays: [CoachContextDay]
    ) async throws -> PreStartCoachIntro {
        let availability = await provider.availability()
        guard availability.isAvailable else {
            return engineIntro(for: brief, summary: summary)
        }

        let prompt = """
        Introduce today's prescribed session in 2-3 terse sentences.
        Title: \(brief.title)
        Summary: \(brief.summary)
        Rationale: \(brief.rationale.joined(separator: "; "))
        Exercises: \(summary.exercises.map(\.displayName).joined(separator: ", "))
        Invite the athlete to ask about volume, swaps, or readiness before starting.
        Do not propose plan changes unless asked.
        """

        let budget = TokenBudget.maxInputTokens(for: .gemini)
        let built = ContextBuilder.build(
            profile: profile,
            days: CoachContextDays(recent: contextDays),
            budget: budget,
            turn: .initial
        )

        let stream = try await provider.respond(
            systemInstructions: built.systemInstructions,
            contextBlock: built.contextBlock,
            userMessage: prompt,
            thread: .empty
        )

        var assembled = ""
        for try await chunk in stream {
            assembled += chunk
        }
        let trimmed = assembled.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return engineIntro(for: brief, summary: summary)
        }
        return PreStartCoachIntro(text: trimmed, isEngineOnly: false)
    }

    public func proposeAdjustment(
        userMessage: String,
        prescription: SessionPrescription,
        excludedExerciseIDs: Set<String>,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        contextDays: [CoachContextDay],
        thread: CoachThreadState = .empty
    ) async throws -> CoachSessionProposal {
        let snapshot = PrescriptionCoachSnapshotBuilder.snapshot(from: prescription)
        return try await inSessionCoach.proposeAdjustment(
            userMessage: userMessage,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs,
            provider: provider,
            profile: profile,
            contextDays: contextDays,
            thread: thread
        )
    }

    public func applyProposal(
        _ proposal: CoachSessionProposal,
        prescription: SessionPrescription,
        excludedExerciseIDs: Set<String>,
        day: HelmDay
    ) throws -> SessionPrescription {
        try applyAdjustmentToPrescription(
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
    ) throws -> SessionPrescription {
        let snapshot = PrescriptionCoachSnapshotBuilder.snapshot(from: prescription)
        let stampedPayload = LoadAdjustmentIntentClassifier.stamp(
            payload: proposal.payload,
            userMessage: nil
        )
        let sessionExerciseIDs = Set(snapshot.session.exercises.map(\.exerciseID))
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
            familiarExerciseIDs: familiarExerciseIDs
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
            PrescriptionDayStore.save(titled, for: day)
            return titled
        }
    }
}
