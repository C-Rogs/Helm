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
            setDelta: operation.setDelta
        )
    }

    private static func mapKind(_ kind: SessionAdjustmentOperation.Kind) -> PrescriptionAdjustmentOperation.Kind {
        switch kind {
        case .swap: .swap
        case .reorder: .reorder
        case .adjustSets: .adjustSets
        }
    }
}
