import Core
import NutritionKit
import PlanKit

enum NutritionDayTypeResolver {
    static func resolve(
        prescriptionSummary: PrescribedSessionSummary?,
        targetMuscles: [MuscleGroup],
        mesocycleState: MesocycleState?
    ) -> NutritionDayType {
        guard let summary = prescriptionSummary, summary.totalSets > 0 else {
            return .rest
        }

        if let mesocycleState {
            for muscle in targetMuscles where mesocycleState.muscles[muscle]?.phase == .deload {
                return .deload
            }
        }

        return .training
    }
}
