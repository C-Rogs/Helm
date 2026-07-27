import Core
import DesignSystem
import Foundation

enum WorkoutSetMilestonePolicy {
    static func encouragementGlyph(
        for completedSet: SetEntryDraft,
        in exerciseSets: [SetEntryDraft],
        excludingLast lastGlyph: EncouragementGlyph?
    ) -> EncouragementGlyph? {
        guard completedSet.status == .completed, !completedSet.setType.isWarmup else { return nil }

        let workingSets = exerciseSets.filter { !$0.setType.isWarmup }
        guard !workingSets.isEmpty,
              let index = workingSets.firstIndex(where: { $0.id == completedSet.id }) else {
            return nil
        }

        let count = workingSets.count
        let middleIndex = Int((Double(count - 1) / 2.0).rounded())
        let isMilestone = index == 0 || index == middleIndex || index == count - 1
        guard isMilestone else { return nil }

        return EncouragementGlyph.random(excludingLast: lastGlyph)
    }
}
