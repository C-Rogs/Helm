import CoachLLM
import Core
import Foundation
import Persistence
import PlanKit

public struct AppliedSessionAdjustment: Sendable, Equatable {
    public let banner: SessionAdjustmentBannerModel
    public let previousExercises: [WorkoutSessionExerciseDraft]
    public let swappedExerciseIDs: [String]

    public init(
        banner: SessionAdjustmentBannerModel,
        previousExercises: [WorkoutSessionExerciseDraft],
        swappedExerciseIDs: [String]
    ) {
        self.banner = banner
        self.previousExercises = previousExercises
        self.swappedExerciseIDs = swappedExerciseIDs
    }
}

public enum InSessionCoachError: Error, Sendable, Equatable {
    case noActiveSession
    case adjustmentRejected(PrescriptionClampReason)
    case providerUnavailable(String)
}

public struct InSessionCoachService: Sendable {
    private let persistence: PersistenceStore

    public init(persistence: PersistenceStore) {
        self.persistence = persistence
    }

    public func askCoachInSession(
        userMessage: String,
        snapshot: ActiveSessionSnapshot,
        excludedExerciseIDs: Set<String>,
        provider: any CoachLLMProvider,
        profile: MemoryProfile,
        contextDays: [CoachContextDay]
    ) async throws -> AppliedSessionAdjustment {
        let availability = await provider.availability()
        guard availability.isAvailable else {
            let message: String
            if case .unavailable(_, let helpText) = availability {
                message = helpText ?? "Coach unavailable"
            } else {
                message = "Coach unavailable"
            }
            throw InSessionCoachError.providerUnavailable(message)
        }

        guard let gemini = provider as? GeminiProvider else {
            throw InSessionCoachError.providerUnavailable("Session adjustments require Gemini.")
        }

        let prompt = buildPrompt(
            snapshot: snapshot,
            profile: profile,
            contextDays: contextDays,
            excludedExerciseIDs: excludedExerciseIDs
        )

        let artefact = try await gemini.generateSessionAdjustment(
            systemInstructions: prompt.systemInstructions,
            contextBlock: prompt.contextBlock,
            userMessage: userMessage,
            thread: .empty
        )

        return try applyAdjustment(
            payload: artefact.payload,
            snapshot: snapshot,
            excludedExerciseIDs: excludedExerciseIDs,
            modelVersion: artefact.schemaVersion.rawValue
        )
    }

    public func applyAdjustment(
        payload: SessionAdjustmentPayload,
        snapshot: ActiveSessionSnapshot,
        excludedExerciseIDs: Set<String>,
        modelVersion: String? = CoachOutputSchemaVersion.sessionAdjustmentV1.rawValue
    ) throws -> AppliedSessionAdjustment {
        let currentPrescription = ActiveSessionPrescriptionBridge.prescribedSession(from: snapshot)
        let (catalog, familiarExerciseIDs) = try loadCatalog()
        let adjustment = SessionAdjustmentMapper.prescriptionAdjustment(from: payload)

        let result = PlanKit.apply(
            adjustment: adjustment,
            to: currentPrescription,
            excluding: excludedExerciseIDs,
            catalog: catalog,
            familiarExerciseIDs: familiarExerciseIDs
        )

        switch result {
        case .rejected(let reason):
            throw InSessionCoachError.adjustmentRejected(reason)
        case .applied(let adjusted):
            let previousExercises = snapshot.session.exercises
            try persistence.activeSessions.syncFromPrescription(
                sessionID: snapshot.session.id,
                prescription: adjusted,
                timestamp: Date()
            )

            let recommendation = try logRecommendation(
                sessionID: snapshot.session.id,
                payload: payload,
                modelVersion: modelVersion
            )

            let banner = try makeBanner(
                payload: payload,
                previous: currentPrescription,
                adjusted: adjusted
            )

            return AppliedSessionAdjustment(
                banner: SessionAdjustmentBannerModel(
                    fromLabel: banner.fromLabel,
                    toLabel: banner.toLabel,
                    reason: payload.rationale,
                    recommendationID: recommendation.id
                ),
                previousExercises: previousExercises,
                swappedExerciseIDs: swappedExerciseIDs(
                    payload: payload,
                    previous: currentPrescription,
                    adjusted: adjusted
                )
            )
        }
    }

    private func buildPrompt(
        snapshot: ActiveSessionSnapshot,
        profile: MemoryProfile,
        contextDays: [CoachContextDay],
        excludedExerciseIDs: Set<String>
    ) -> CoachPrompt {
        var context = ContextBuilder.build(
            profile: profile,
            days: CoachContextDays(recent: contextDays),
            budget: TokenBudget.maxInputTokens(for: .gemini),
            turn: .followUp
        ).contextBlock

        let exerciseLines = snapshot.session.exercises
            .sorted { $0.displayOrder < $1.displayOrder }
            .map { exercise in
                let completed = exercise.sets.filter { $0.status == .completed }.count
                return "\(exercise.exerciseID) (sets \(exercise.sets.count), completed \(completed))"
            }
            .joined(separator: "\n")

        if !exerciseLines.isEmpty {
            context += "\n\nActive session exercises:\n\(exerciseLines)"
        }
        if !excludedExerciseIDs.isEmpty {
            context += "\n\nExcluded exercise IDs (already swapped this session):\n"
                + excludedExerciseIDs.sorted().joined(separator: ", ")
        }

        return CoachPrompt(
            systemInstructions: CoachSystemPrompt.sessionAdjustmentV1,
            contextBlock: context,
            estimatedTokens: TokenBudget.estimateTokens(characterCount: context.count),
            includedDayCount: contextDays.count,
            droppedDayCount: 0
        )
    }

    private func loadCatalog() throws -> (catalog: [CatalogExercise], familiarExerciseIDs: Set<String>) {
        let rows = try persistence.exercises.fetchCatalogRows()
        let day = HelmDay.day(for: Date(), cutoff: .default, calendar: .current)
        let history = try PrescriptionHistoryBuilder.history(
            from: persistence,
            endingAt: day
        )
        let familiarExerciseIDs = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
        let catalog = PrescriptionCatalogBuilder.build(
            from: rows,
            familiarExerciseIDs: familiarExerciseIDs
        )
        return (catalog, familiarExerciseIDs)
    }

    private func logRecommendation(
        sessionID: String,
        payload: SessionAdjustmentPayload,
        modelVersion: String?
    ) throws -> StoredCoachRecommendation {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        let json = String(decoding: data, as: UTF8.self)

        let stored = try persistence.coachRecommendations.insert(
            CoachRecommendationInsert(
                scope: .session,
                workoutSessionID: sessionID,
                recommendationType: .sessionAdjustment,
                payloadJSON: json,
                modelVersion: modelVersion
            )
        )
        try persistence.coachRecommendations.markActedOn(id: stored.id)
        return stored
    }

    private func makeBanner(
        payload: SessionAdjustmentPayload,
        previous: SessionPrescription,
        adjusted: SessionPrescription
    ) throws -> (fromLabel: String, toLabel: String) {
        let names = try persistence.exercises.displayNames(
            for: Array(Set(previous.exercises.map(\.exerciseID) + adjusted.exercises.map(\.exerciseID)))
        )

        if let operation = payload.operations.first {
            switch operation.kind {
            case .swap:
                let fromID = operation.fromExerciseID ?? previous.exercises.first?.exerciseID ?? "Exercise"
                let toID = operation.toExerciseID
                    ?? adjusted.exercises.first(where: { $0.exerciseID != fromID })?.exerciseID
                    ?? adjusted.exercises.first?.exerciseID
                    ?? fromID
                return (
                    names[fromID] ?? fromID,
                    names[toID] ?? toID
                )
            case .reorder:
                return ("Exercise order", "Updated")
            case .adjustSets:
                let exerciseID = operation.exerciseID ?? previous.exercises.first?.exerciseID ?? "Exercise"
                let delta = operation.setDelta ?? 0
                let sign = delta > 0 ? "+\(delta)" : "\(delta)"
                return (names[exerciseID] ?? exerciseID, "\(sign) sets")
            }
        }

        return ("Session", "Updated")
    }

    private func swappedExerciseIDs(
        payload: SessionAdjustmentPayload,
        previous: SessionPrescription,
        adjusted: SessionPrescription
    ) -> [String] {
        var ids: [String] = []
        for operation in payload.operations where operation.kind == .swap {
            if let from = operation.fromExerciseID {
                ids.append(from)
            }
            if let to = operation.toExerciseID {
                ids.append(to)
            } else if let from = operation.fromExerciseID,
                      let index = previous.exercises.firstIndex(where: { $0.exerciseID == from }),
                      adjusted.exercises.indices.contains(index) {
                ids.append(adjusted.exercises[index].exerciseID)
            }
        }
        return ids
    }
}
