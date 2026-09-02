import CoachLLM
import Core
import Foundation
import PlanKit

enum SessionAdjustmentMapper {
    static func prescriptionAdjustment(from payload: SessionAdjustmentPayload) -> PrescriptionAdjustment {
        PrescriptionAdjustment(operations: payload.operations.map(mapOperation))
    }

    private static func mapOperation(_ operation: SessionAdjustmentOperation) -> PrescriptionAdjustmentOperation {
        PrescriptionAdjustmentOperation(
            kind: mapKind(operation.kind),
            fromExerciseID: operation.fromExerciseID,
            toExerciseID: operation.toExerciseID,
            excludeExerciseIDs: operation.excludeExerciseIDs,
            orderedExerciseIDs: operation.orderedExerciseIDs,
            exerciseID: operation.exerciseID,
            setDelta: operation.setDelta,
            massDeltaKg: operation.massDeltaKg,
            targetMassKg: operation.targetMassKg,
            rpeDelta: operation.rpeDelta,
            targetRPE: operation.targetRPE,
            loadAdjustmentIntent: operation.loadAdjustmentIntent ?? .coachSuggested,
            targetSets: operation.targetSets,
            warmupSets: operation.warmupSets,
            targetReps: operation.targetReps
        )
    }

    private static func mapKind(_ kind: SessionAdjustmentOperation.Kind) -> PrescriptionAdjustmentOperation.Kind {
        switch kind {
        case .swap: .swap
        case .reorder: .reorder
        case .adjustSets: .adjustSets
        case .adjustWarmupSets: .adjustWarmupSets
        case .adjustLoad: .adjustLoad
        case .adjustRPE: .adjustRPE
        case .addExercise: .addExercise
        }
    }
}
