import Core
import Foundation

public extension PhaseGoal {
    /// Valid PlanKit muscle groups from `musclePriorities`, capped to 1…3.
    var resolvedMusclePriorities: [MuscleGroup] {
        MusclePriorityRedistribution.normalize(
            musclePriorities.compactMap(MuscleGroup.init(rawValue:))
        )
    }

    /// Athlete-facing focus readout, e.g. `Chest · Back`. Nil when empty.
    var musclePrioritiesDisplayLabel: String? {
        let labels = resolvedMusclePriorities.map(\.displayLabel)
        guard !labels.isEmpty else { return nil }
        return labels.joined(separator: " · ")
    }
}
