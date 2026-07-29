import Core
import Foundation
import PlanKit

/// Adds emphasis-muscle slots to each session without collapsing the weekly split rotation.
enum EmphasisVolumePolicy {
    static func augmentedTargetMuscles(
        base: [MuscleGroup],
        emphasis: String?
    ) -> [MuscleGroup] {
        let extras = supplementaryMuscles(for: emphasis)
        guard !extras.isEmpty else { return base }

        var result = base
        for muscle in extras where !result.contains(muscle) {
            result.append(muscle)
        }
        return result
    }

    static func supplementaryMuscles(for emphasis: String?) -> [MuscleGroup] {
        let normalized = emphasis?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !normalized.isEmpty else { return [] }

        if normalized.contains("arm") {
            return [.biceps, .triceps]
        }
        if normalized.contains("leg") {
            return [.quads, .hamstrings]
        }
        if normalized.contains("v-taper") || normalized.contains("vtaper") {
            return [.shoulders, .back]
        }
        return []
    }
}
