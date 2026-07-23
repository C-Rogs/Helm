import Core
import Foundation

public struct PrescriptionAdjustment: Sendable, Hashable, Codable {
    public let operations: [PrescriptionAdjustmentOperation]

    public init(operations: [PrescriptionAdjustmentOperation]) {
        self.operations = operations
    }
}

public struct PrescriptionAdjustmentOperation: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Hashable, Codable {
        case swap
        case reorder
        case adjustSets
    }

    public let kind: Kind
    public let fromExerciseID: String?
    public let toExerciseID: String?
    public let excludeExerciseIDs: [String]?
    public let orderedExerciseIDs: [String]?
    public let exerciseID: String?
    public let setDelta: Int?

    public init(
        kind: Kind,
        fromExerciseID: String? = nil,
        toExerciseID: String? = nil,
        excludeExerciseIDs: [String]? = nil,
        orderedExerciseIDs: [String]? = nil,
        exerciseID: String? = nil,
        setDelta: Int? = nil
    ) {
        self.kind = kind
        self.fromExerciseID = fromExerciseID
        self.toExerciseID = toExerciseID
        self.excludeExerciseIDs = excludeExerciseIDs
        self.orderedExerciseIDs = orderedExerciseIDs
        self.exerciseID = exerciseID
        self.setDelta = setDelta
    }
}

public enum PrescriptionClampReason: Sendable, Hashable, Codable, Equatable {
    case setsBelowMinimum(exerciseID: String)
    case setsAboveMaximum(exerciseID: String)
    case swapTargetExcluded(exerciseID: String)
    case swapNoAlternativeAvailable(fromExerciseID: String)
    case invalidReorder(missingExerciseIDs: [String])
    case exerciseNotFound(exerciseID: String)
}

public enum PrescriptionAdjustmentResult: Sendable, Hashable, Equatable {
    case applied(PrescribedSession)
    case rejected(PrescriptionClampReason)
}

enum PrescriptionAdjustmentEngine {
    private enum OperationOutcome {
        case success
        case failure(PrescriptionClampReason)
    }

    static func apply(
        adjustment: PrescriptionAdjustment,
        to session: PrescribedSession,
        excluding excludedExerciseIDs: Set<String>,
        catalog: [CatalogExercise]
    ) -> PrescriptionAdjustmentResult {
        var exercises = session.exercises.sorted { $0.order < $1.order }
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.exerciseID, $0) })

        for operation in adjustment.operations {
            switch applyOperation(
                operation,
                to: &exercises,
                excluding: excludedExerciseIDs,
                catalog: catalog,
                catalogByID: catalogByID
            ) {
            case .success:
                continue
            case .failure(let reason):
                return .rejected(reason)
            }
        }

        return .applied(PrescribedSession(
            id: session.id,
            helmDay: session.helmDay,
            exercises: exercises
        ))
    }

    private static func applyOperation(
        _ operation: PrescriptionAdjustmentOperation,
        to exercises: inout [PrescribedExercise],
        excluding excludedExerciseIDs: Set<String>,
        catalog: [CatalogExercise],
        catalogByID: [String: CatalogExercise]
    ) -> OperationOutcome {
        switch operation.kind {
        case .swap:
            return applySwap(
                operation,
                to: &exercises,
                excluding: excludedExerciseIDs,
                catalog: catalog,
                catalogByID: catalogByID
            )
        case .reorder:
            return applyReorder(operation, to: &exercises)
        case .adjustSets:
            return applySetAdjustment(operation, to: &exercises)
        }
    }

    private static func applySwap(
        _ operation: PrescriptionAdjustmentOperation,
        to exercises: inout [PrescribedExercise],
        excluding excludedExerciseIDs: Set<String>,
        catalog: [CatalogExercise],
        catalogByID: [String: CatalogExercise]
    ) -> OperationOutcome {
        guard let fromID = operation.fromExerciseID else {
            return .failure(.exerciseNotFound(exerciseID: ""))
        }
        guard let index = exercises.firstIndex(where: { $0.exerciseID == fromID }) else {
            return .failure(.exerciseNotFound(exerciseID: fromID))
        }

        let blocked = excludedExerciseIDs
            .union(Set(operation.excludeExerciseIDs ?? []))
            .union([fromID])

        let toID: String
        if let requested = operation.toExerciseID {
            if excludedExerciseIDs.contains(requested) {
                return .failure(.swapTargetExcluded(exerciseID: requested))
            }
            toID = requested
        } else {
            guard let primaryMuscle = catalogByID[fromID]?.muscleMap.contributions
                .max(by: { $0.fraction < $1.fraction })?.muscle,
                let alternative = PrescriptionEngine.bestExercise(
                    for: primaryMuscle,
                    catalog: catalog,
                    excluding: blocked
                )
            else {
                return .failure(.swapNoAlternativeAvailable(fromExerciseID: fromID))
            }
            toID = alternative.exerciseID
        }

        if excludedExerciseIDs.contains(toID) {
            return .failure(.swapTargetExcluded(exerciseID: toID))
        }

        exercises[index] = replacing(exercises[index], exerciseID: toID)
        return .success
    }

    private static func applyReorder(
        _ operation: PrescriptionAdjustmentOperation,
        to exercises: inout [PrescribedExercise]
    ) -> OperationOutcome {
        guard let orderedIDs = operation.orderedExerciseIDs else {
            return .failure(.invalidReorder(missingExerciseIDs: []))
        }
        let currentIDs = Set(exercises.map(\.exerciseID))
        let missing = orderedIDs.filter { !currentIDs.contains($0) }
        if !missing.isEmpty {
            return .failure(.invalidReorder(missingExerciseIDs: missing))
        }

        var reordered: [PrescribedExercise] = []
        for (order, exerciseID) in orderedIDs.enumerated() {
            guard let exercise = exercises.first(where: { $0.exerciseID == exerciseID }) else {
                return .failure(.invalidReorder(missingExerciseIDs: [exerciseID]))
            }
            reordered.append(replacing(exercise, order: order))
        }
        exercises = reordered
        return .success
    }

    private static func applySetAdjustment(
        _ operation: PrescriptionAdjustmentOperation,
        to exercises: inout [PrescribedExercise]
    ) -> OperationOutcome {
        guard let exerciseID = operation.exerciseID, let delta = operation.setDelta else {
            return .failure(.exerciseNotFound(exerciseID: operation.exerciseID ?? ""))
        }
        guard let index = exercises.firstIndex(where: { $0.exerciseID == exerciseID }) else {
            return .failure(.exerciseNotFound(exerciseID: exerciseID))
        }

        let proposed = exercises[index].targetSets + delta
        if proposed < PrescriptionBounds.minSetsPerExercise {
            return .failure(.setsBelowMinimum(exerciseID: exerciseID))
        }
        if proposed > PrescriptionBounds.maxSetsPerExercise {
            return .failure(.setsAboveMaximum(exerciseID: exerciseID))
        }

        exercises[index] = replacing(exercises[index], targetSets: proposed)
        return .success
    }

    private static func replacing(
        _ exercise: PrescribedExercise,
        exerciseID: String? = nil,
        order: Int? = nil,
        targetSets: Int? = nil
    ) -> PrescribedExercise {
        PrescribedExercise(
            id: exercise.id,
            exerciseID: exerciseID ?? exercise.exerciseID,
            order: order ?? exercise.order,
            targetSets: targetSets ?? exercise.targetSets,
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            targetMass: exercise.targetMass,
            targetRPE: exercise.targetRPE,
            rationale: exercise.rationale,
            evidenceIDs: exercise.evidenceIDs
        )
    }
}
