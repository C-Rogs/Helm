import CoachLLM
import Core
import Foundation
import Persistence

enum SessionExerciseIDResolver {
    struct Result: Sendable, Equatable {
        let payload: SessionAdjustmentPayload
        let unresolvedExerciseIDs: [String]
    }

    static func normalize(
        payload: SessionAdjustmentPayload,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore
    ) throws -> Result {
        var unresolved: [String] = []
        let normalizedOps = payload.operations.map { operation in
            mapOperation(
                operation,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                unresolved: &unresolved
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
            unresolvedExerciseIDs: Array(Set(unresolved)).sorted()
        )
    }

    private static func mapOperation(
        _ operation: SessionAdjustmentOperation,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore,
        unresolved: inout [String]
    ) -> SessionAdjustmentOperation {
        switch operation.kind {
        case .swap:
            let from = resolve(
                operation.fromExerciseID,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                mustBeInSession: true,
                unresolved: &unresolved
            )
            let to = resolve(
                operation.toExerciseID,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                mustBeInSession: false,
                unresolved: &unresolved
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
                targetRPE: operation.targetRPE
            )
        case .reorder:
            let ordered = operation.orderedExerciseIDs?.map { id in
                resolve(
                    id,
                    sessionExerciseIDs: sessionExerciseIDs,
                    exerciseDisplayNames: exerciseDisplayNames,
                    persistence: persistence,
                    mustBeInSession: true,
                    unresolved: &unresolved
                ) ?? id
            }
            return SessionAdjustmentOperation(
                kind: operation.kind,
                orderedExerciseIDs: ordered
            )
        case .adjustSets, .adjustLoad, .adjustRPE:
            let exerciseID = resolve(
                operation.exerciseID,
                sessionExerciseIDs: sessionExerciseIDs,
                exerciseDisplayNames: exerciseDisplayNames,
                persistence: persistence,
                mustBeInSession: true,
                unresolved: &unresolved
            )
            return SessionAdjustmentOperation(
                kind: operation.kind,
                exerciseID: exerciseID,
                setDelta: operation.setDelta,
                massDeltaKg: operation.massDeltaKg,
                targetMassKg: operation.targetMassKg,
                rpeDelta: operation.rpeDelta,
                targetRPE: operation.targetRPE
            )
        }
    }

    private static func resolve(
        _ rawID: String?,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String],
        persistence: PersistenceStore,
        mustBeInSession: Bool,
        unresolved: inout [String]
    ) -> String? {
        guard let rawID, !rawID.isEmpty else { return rawID }

        if sessionExerciseIDs.contains(rawID) {
            return rawID
        }

        if let matched = displayNameMatch(
            rawID,
            sessionExerciseIDs: sessionExerciseIDs,
            exerciseDisplayNames: exerciseDisplayNames
        ) {
            return matched
        }

        if let matched = fuzzyMatch(rawID, against: sessionExerciseIDs) {
            return matched
        }

        if let resolved = try? persistence.exercises.resolveImportedTitle(rawID)?.exerciseID {
            if !mustBeInSession || sessionExerciseIDs.contains(resolved) {
                return resolved
            }
        }

        let normalized = normalizeToken(rawID)
        if let aliasMatch = try? persistence.exercises.resolveExerciseID(normalizedAlias: normalized) {
            if !mustBeInSession || sessionExerciseIDs.contains(aliasMatch) {
                return aliasMatch
            }
        }

        unresolved.append(rawID)
        return rawID
    }

    private static func displayNameMatch(
        _ rawID: String,
        sessionExerciseIDs: Set<String>,
        exerciseDisplayNames: [String: String]
    ) -> String? {
        let rawCandidates = Set(ExerciseSearchNormalizer.searchCandidates(for: rawID))
        guard !rawCandidates.isEmpty else { return nil }

        for sessionID in sessionExerciseIDs {
            let label = ExerciseDisplayFormatter.friendlyName(
                for: sessionID,
                displayNames: exerciseDisplayNames
            )
            let labelCandidates = Set(ExerciseSearchNormalizer.searchCandidates(for: label))
            if !rawCandidates.isDisjoint(with: labelCandidates) {
                return sessionID
            }
        }
        return nil
    }

    private static func fuzzyMatch(_ rawID: String, against sessionExerciseIDs: Set<String>) -> String? {
        let needle = normalizeToken(rawID)
        for sessionID in sessionExerciseIDs {
            if normalizeToken(sessionID) == needle {
                return sessionID
            }
        }
        return nil
    }

    private static func normalizeToken(_ value: String) -> String {
        var token = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("seed-") {
            token = String(token.dropFirst(5))
        }
        return token
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}
