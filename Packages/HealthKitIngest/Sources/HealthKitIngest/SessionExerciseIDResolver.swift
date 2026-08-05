import CoachLLM
import Core
import Foundation
import Persistence

enum SessionExerciseIDResolver {
    struct Result: Sendable, Equatable {
        let payload: SessionAdjustmentPayload
        let unresolvedExerciseIDs: [String]
        let catalogCandidates: [String]
    }

    static func normalize(
        payload: SessionAdjustmentPayload,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore,
        excludedExerciseIDs: Set<String> = [],
        familiarExerciseIDs: Set<String> = [],
        recentExerciseIDs: Set<String> = [],
        phraseHint: String? = nil
    ) throws -> Result {
        var unresolved: [String] = []
        var catalogCandidates: [String] = []
        let normalizedOps = payload.operations.map { operation in
            mapOperation(
                operation,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                excludedExerciseIDs: excludedExerciseIDs,
                familiarExerciseIDs: familiarExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                phraseHint: phraseHint,
                unresolved: &unresolved,
                catalogCandidates: &catalogCandidates
            )
        }

        let normalized = SessionAdjustmentPayload(
            schemaVersion: payload.schemaVersion,
            reply: payload.reply,
            rationale: payload.rationale,
            operations: normalizedOps
        )

        return Result(
            payload: normalized,
            unresolvedExerciseIDs: Array(Set(unresolved)).sorted(),
            catalogCandidates: Array(Set(catalogCandidates)).sorted()
        )
    }

    private static func mapOperation(
        _ operation: SessionAdjustmentOperation,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore,
        excludedExerciseIDs: Set<String>,
        familiarExerciseIDs: Set<String>,
        recentExerciseIDs: Set<String>,
        phraseHint: String?,
        unresolved: inout [String],
        catalogCandidates: inout [String]
    ) -> SessionAdjustmentOperation {
        switch operation.kind {
        case .swap:
            let from = resolve(
                operation.fromExerciseID,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                excludedExerciseIDs: excludedExerciseIDs,
                familiarExerciseIDs: familiarExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                phraseHint: nil,
                mustBeInSession: true,
                unresolved: &unresolved,
                catalogCandidates: &catalogCandidates
            )
            let to = resolve(
                operation.toExerciseID,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                excludedExerciseIDs: excludedExerciseIDs,
                familiarExerciseIDs: familiarExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                phraseHint: phraseHint,
                mustBeInSession: false,
                unresolved: &unresolved,
                catalogCandidates: &catalogCandidates
            )
            return SessionAdjustmentOperation(
                kind: operation.kind,
                fromExerciseID: from,
                toExerciseID: to,
                excludeExerciseIDs: operation.excludeExerciseIDs,
                orderedExerciseIDs: operation.orderedExerciseIDs,
                exerciseID: operation.exerciseID,
                setDelta: operation.setDelta,
                massDeltaKg: operation.massDeltaKg,
                targetMassKg: operation.targetMassKg,
                rpeDelta: operation.rpeDelta,
                targetRPE: operation.targetRPE,
                loadAdjustmentIntent: operation.loadAdjustmentIntent,
                targetSets: operation.targetSets
            )
        case .reorder:
            let ordered = operation.orderedExerciseIDs?.map { id in
                resolve(
                    id,
                    sessionExerciseIDs: sessionExerciseIDs,
                    exerciseDisplayNames: exerciseDisplayNames,
                    persistence: persistence,
                    excludedExerciseIDs: excludedExerciseIDs,
                    familiarExerciseIDs: familiarExerciseIDs,
                    recentExerciseIDs: recentExerciseIDs,
                    phraseHint: nil,
                    mustBeInSession: true,
                    unresolved: &unresolved,
                    catalogCandidates: &catalogCandidates
                ) ?? id
            }
            return SessionAdjustmentOperation(
                kind: operation.kind,
                orderedExerciseIDs: ordered
            )
        case .adjustSets, .adjustWarmupSets, .adjustLoad, .adjustRPE:
            let exerciseID = resolve(
                operation.exerciseID,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                excludedExerciseIDs: excludedExerciseIDs,
                familiarExerciseIDs: familiarExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                phraseHint: nil,
                mustBeInSession: true,
                unresolved: &unresolved,
                catalogCandidates: &catalogCandidates
            )
            return SessionAdjustmentOperation(
                kind: operation.kind,
                exerciseID: exerciseID,
                setDelta: operation.setDelta,
                massDeltaKg: operation.massDeltaKg,
                targetMassKg: operation.targetMassKg,
                rpeDelta: operation.rpeDelta,
                targetRPE: operation.targetRPE,
                loadAdjustmentIntent: operation.loadAdjustmentIntent
            )
        case .addExercise:
            let to = resolve(
                operation.toExerciseID,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                excludedExerciseIDs: excludedExerciseIDs,
                familiarExerciseIDs: familiarExerciseIDs,
                recentExerciseIDs: recentExerciseIDs,
                phraseHint: phraseHint,
                mustBeInSession: false,
                unresolved: &unresolved,
                catalogCandidates: &catalogCandidates
            )
            return SessionAdjustmentOperation(
                kind: operation.kind,
                toExerciseID: to,
                targetSets: operation.targetSets
            )
        }
    }

    private static func resolve(
        _ rawID: String?,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore,
        excludedExerciseIDs: Set<String>,
        familiarExerciseIDs: Set<String>,
        recentExerciseIDs: Set<String>,
        phraseHint: String?,
        mustBeInSession: Bool,
        unresolved: inout [String],
        catalogCandidates: inout [String]
    ) -> String? {
        guard let rawID, !rawID.isEmpty else { return rawID }

        let context = ExerciseResolver.Context(
            sessionExerciseIDs: sessionExerciseIDs,
            exerciseDisplayNames: exerciseDisplayNames,
            excludedExerciseIDs: excludedExerciseIDs,
            familiarExerciseIDs: familiarExerciseIDs,
            recentExerciseIDs: recentExerciseIDs,
            mustBeInSession: mustBeInSession,
            phraseHint: phraseHint
        )
        let resolved = ExerciseResolver.resolve(rawID, context: context, persistence: persistence)
        if let exerciseID = resolved.exerciseID {
            return exerciseID
        }

        unresolved.append(rawID)
        catalogCandidates.append(contentsOf: resolved.catalogCandidates)
        return rawID
    }
}
