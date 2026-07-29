import Core
import Foundation
import PlanKit

/// Adds emphasis-muscle slots to each session without collapsing the weekly split rotation.
enum EmphasisVolumePolicy {
    static func augmentedTargetMuscles(
        base: [MuscleGroup],
        emphasis: String?
    ) -> [MuscleGroup] {
        PlanKit.EmphasisVolumePolicy.augmentedTargetMuscles(base: base, emphasis: emphasis)
    }

    static func supplementaryMuscles(for emphasis: String?) -> [MuscleGroup] {
        PlanKit.EmphasisVolumePolicy.supplementaryMuscles(for: emphasis)
    }
}
