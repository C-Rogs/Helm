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
        case adjustWarmupSets
        case adjustLoad
        case adjustRPE
        case addExercise
    }

    public let kind: Kind
    public let fromExerciseID: String?
    public let toExerciseID: String?
    public let excludeExerciseIDs: [String]?
    public let orderedExerciseIDs: [String]?
    public let exerciseID: String?
    public let setDelta: Int?
    public let massDeltaKg: Double?
    public let targetMassKg: Double?
    public let rpeDelta: Double?
    public let targetRPE: Double?
    public let loadAdjustmentIntent: LoadAdjustmentIntent
    public let targetSets: Int?
    public let warmupSets: Int?

    public init(
        kind: Kind,
        fromExerciseID: String? = nil,
        toExerciseID: String? = nil,
        excludeExerciseIDs: [String]? = nil,
        orderedExerciseIDs: [String]? = nil,
        exerciseID: String? = nil,
        setDelta: Int? = nil,
        massDeltaKg: Double? = nil,
        targetMassKg: Double? = nil,
        rpeDelta: Double? = nil,
        targetRPE: Double? = nil,
        loadAdjustmentIntent: LoadAdjustmentIntent = .coachSuggested,
        targetSets: Int? = nil,
        warmupSets: Int? = nil
    ) {
        self.kind = kind
        self.fromExerciseID = fromExerciseID
        self.toExerciseID = toExerciseID
        self.excludeExerciseIDs = excludeExerciseIDs
        self.orderedExerciseIDs = orderedExerciseIDs
        self.exerciseID = exerciseID
        self.setDelta = setDelta
        self.massDeltaKg = massDeltaKg
        self.targetMassKg = targetMassKg
        self.rpeDelta = rpeDelta
        self.targetRPE = targetRPE
        self.loadAdjustmentIntent = loadAdjustmentIntent
        self.targetSets = targetSets
        self.warmupSets = warmupSets
    }
}

public enum PrescriptionClampReason: Sendable, Hashable, Codable, Equatable {
    case swapTargetExcluded(exerciseID: String)
    case swapNoAlternativeAvailable(fromExerciseID: String)
    case invalidReorder(missingExerciseIDs: [String])
    case exerciseNotFound(exerciseID: String)
    case duplicateExercise(exerciseID: String)
    case loadMissing(exerciseID: String)
    case rpeMissing(exerciseID: String)
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
        catalog: [CatalogExercise],
        availableEquipment: Set<String>? = nil,
        familiarExerciseIDs: Set<String> = []
    ) -> PrescriptionAdjustmentResult {
        var exercises = session.exercises.sorted { $0.order < $1.order }
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.exerciseID, $0) })

        for operation in adjustment.operations {
            switch applyOperation(
                operation,
                to: &exercises,
                excluding: excludedExerciseIDs,
                catalog: catalog,
                catalogByID: catalogByID,
                availableEquipment: availableEquipment,
                familiarExerciseIDs: familiarExerciseIDs
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
        catalogByID: [String: CatalogExercise],
        availableEquipment: Set<String>?,
        familiarExerciseIDs: Set<String>
    ) -> OperationOutcome {
        switch operation.kind {
        case .swap:
            return applySwap(
                operation,
                to: &exercises,
                excluding: excludedExerciseIDs,
                catalog: catalog,
                catalogByID: catalogByID,
                availableEquipment: availableEquipment,
                familiarExerciseIDs: familiarExerciseIDs
            )
        case .reorder:
            return applyReorder(operation, to: &exercises)
        case .adjustSets:
            return applySetAdjustment(operation, to: &exercises)
        case .adjustWarmupSets:
            return applyWarmupSetAdjustment(operation, to: &exercises)
        case .adjustLoad:
            return applyLoadAdjustment(operation, to: &exercises)
        case .adjustRPE:
            return applyRPEAdjustment(operation, to: &exercises)
        case .addExercise:
            return applyAddExercise(operation, to: &exercises, catalogByID: catalogByID)
        }
    }

    private static func applySwap(
        _ operation: PrescriptionAdjustmentOperation,
        to exercises: inout [PrescribedExercise],
        excluding excludedExerciseIDs: Set<String>,
        catalog: [CatalogExercise],
        catalogByID: [String: CatalogExercise],
        availableEquipment: Set<String>?,
        familiarExerciseIDs: Set<String>
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
                    excluding: blocked,
                    availableEquipment: availableEquipment,
                    familiarExerciseIDs: familiarExerciseIDs
                )
            else {
                return .failure(.swapNoAlternativeAvailable(fromExerciseID: fromID))
            }
            toID = alternative.exerciseID
        }

        if excludedExerciseIDs.contains(toID) {
            return .failure(.swapTargetExcluded(exerciseID: toID))
        }

        let primaryMuscle = catalogByID[fromID]?.muscleMap.contributions
            .max(by: { $0.fraction < $1.fraction })?.muscle
        let rationalePayload: (rationale: String, evidenceIDs: [String])
        if let primaryMuscle, let catalogExercise = catalogByID[toID] {
            rationalePayload = ExerciseSelectionEngine.makeRationale(for: catalogExercise, muscle: primaryMuscle)
        } else {
            rationalePayload = (exercises[index].rationale ?? "", exercises[index].evidenceIDs)
        }

        exercises[index] = replacing(
            exercises[index],
            exerciseID: toID,
            rationale: rationalePayload.rationale,
            evidenceIDs: rationalePayload.evidenceIDs
        )
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

        let proposed = max(1, exercises[index].targetSets + delta)
        exercises[index] = replacing(exercises[index], targetSets: proposed)
        return .success
    }

    private static func applyWarmupSetAdjustment(
        _ operation: PrescriptionAdjustmentOperation,
        to exercises: inout [PrescribedExercise]
    ) -> OperationOutcome {
        guard let exerciseID = operation.exerciseID else {
            return .failure(.exerciseNotFound(exerciseID: ""))
        }
        guard let index = exercises.firstIndex(where: { $0.exerciseID == exerciseID }) else {
            return .failure(.exerciseNotFound(exerciseID: exerciseID))
        }

        let proposed: Int
        if let absolute = operation.warmupSets {
            proposed = max(0, absolute)
        } else if let delta = operation.setDelta {
            proposed = max(0, exercises[index].warmupSets + delta)
        } else {
            return .failure(.exerciseNotFound(exerciseID: exerciseID))
        }

        exercises[index] = replacing(exercises[index], warmupSets: proposed)
        return .success
    }

    private static func applyLoadAdjustment(
        _ operation: PrescriptionAdjustmentOperation,
        to exercises: inout [PrescribedExercise]
    ) -> OperationOutcome {
        guard let exerciseID = operation.exerciseID else {
            return .failure(.exerciseNotFound(exerciseID: ""))
        }
        guard let index = exercises.firstIndex(where: { $0.exerciseID == exerciseID }) else {
            return .failure(.exerciseNotFound(exerciseID: exerciseID))
        }

        let proposedKg: Double
        if let targetMassKg = operation.targetMassKg {
            proposedKg = targetMassKg
        } else if let delta = operation.massDeltaKg {
            // A relative move needs something to move from.
            guard let currentMass = exercises[index].targetMass else {
                return .failure(.loadMissing(exerciseID: exerciseID))
            }
            proposedKg = currentMass.kilograms + delta
        } else {
            return .failure(.loadMissing(exerciseID: exerciseID))
        }

        let boundedKg = PrescriptionBounds.clampedLoadKg(proposedKg)
        exercises[index] = replacing(
            exercises[index],
            targetMass: Mass(kilograms: boundedKg)
        )
        return .success
    }

    private static func applyRPEAdjustment(
        _ operation: PrescriptionAdjustmentOperation,
        to exercises: inout [PrescribedExercise]
    ) -> OperationOutcome {
        guard let exerciseID = operation.exerciseID else {
            return .failure(.exerciseNotFound(exerciseID: ""))
        }
        guard let index = exercises.firstIndex(where: { $0.exerciseID == exerciseID }) else {
            return .failure(.exerciseNotFound(exerciseID: exerciseID))
        }

        let currentRPE = exercises[index].targetRPE ?? PrescriptionBounds.minRPE
        let proposedRPE: Double
        if let targetRPE = operation.targetRPE {
            proposedRPE = targetRPE
        } else if let delta = operation.rpeDelta {
            proposedRPE = currentRPE + delta
        } else {
            return .failure(.rpeMissing(exerciseID: exerciseID))
        }

        // Clamp to the RPE scale the logger accepts rather than refusing the change.
        exercises[index] = replacing(
            exercises[index],
            targetRPE: PrescriptionBounds.clampRPE(proposedRPE)
        )
        return .success
    }

    private static func applyAddExercise(
        _ operation: PrescriptionAdjustmentOperation,
        to exercises: inout [PrescribedExercise],
        catalogByID: [String: CatalogExercise]
    ) -> OperationOutcome {
        guard let exerciseID = operation.toExerciseID else {
            return .failure(.exerciseNotFound(exerciseID: ""))
        }
        guard catalogByID[exerciseID] != nil else {
            return .failure(.exerciseNotFound(exerciseID: exerciseID))
        }
        if exercises.contains(where: { $0.exerciseID == exerciseID }) {
            return .failure(.duplicateExercise(exerciseID: exerciseID))
        }

        let setCount = max(1, operation.targetSets ?? 3)
        let warmupCount = max(0, operation.warmupSets ?? 0)
        let targetMass = operation.targetMassKg.map { Mass(kilograms: PrescriptionBounds.clampedLoadKg($0)) }
        exercises.append(
            PrescribedExercise(
                exerciseID: exerciseID,
                order: exercises.count,
                targetSets: setCount,
                warmupSets: warmupCount,
                targetRepMin: nil,
                targetRepMax: nil,
                targetMass: targetMass,
                targetRPE: operation.targetRPE.map { PrescriptionBounds.clampRPE($0) }
            )
        )
        return .success
    }

    private static func replacing(
        _ exercise: PrescribedExercise,
        exerciseID: String? = nil,
        order: Int? = nil,
        targetSets: Int? = nil,
        warmupSets: Int? = nil,
        targetMass: Mass? = nil,
        targetRPE: Double? = nil,
        rationale: String? = nil,
        evidenceIDs: [String]? = nil
    ) -> PrescribedExercise {
        PrescribedExercise(
            id: exercise.id,
            exerciseID: exerciseID ?? exercise.exerciseID,
            order: order ?? exercise.order,
            targetSets: targetSets ?? exercise.targetSets,
            warmupSets: warmupSets ?? exercise.warmupSets,
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            targetMass: targetMass ?? exercise.targetMass,
            targetRPE: targetRPE ?? exercise.targetRPE,
            rationale: rationale ?? exercise.rationale,
            evidenceIDs: evidenceIDs ?? exercise.evidenceIDs
        )
    }
}

public enum PrescriptionDiff {
    public static func exercisesChanged(
        from previous: SessionPrescription,
        to adjusted: SessionPrescription
    ) -> Bool {
        let lhs = normalized(previous.exercises)
        let rhs = normalized(adjusted.exercises)
        return lhs != rhs
    }

    private static func normalized(_ exercises: [PrescribedExercise]) -> [NormalizedExercise] {
        exercises
            .sorted { $0.order < $1.order }
            .map {
                NormalizedExercise(
                    exerciseID: $0.exerciseID,
                    order: $0.order,
                    targetSets: $0.targetSets,
                    warmupSets: $0.warmupSets,
                    targetMassKg: $0.targetMass?.kilograms,
                    targetRPE: $0.targetRPE
                )
            }
    }

    private struct NormalizedExercise: Equatable {
        let exerciseID: String
        let order: Int
        let targetSets: Int
        let warmupSets: Int
        let targetMassKg: Double?
        let targetRPE: Double?
    }
}
