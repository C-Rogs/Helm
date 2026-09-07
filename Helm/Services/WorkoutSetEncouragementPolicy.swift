import Core
import DesignSystem
import Foundation

enum WorkoutSetEncouragementPolicy {
    static func encouragementGlyph(
        for completedSet: SetEntryDraft,
        in exerciseSets: [SetEntryDraft],
        excludingLast lastGlyph: EncouragementGlyph?
    ) -> EncouragementGlyph? {
        guard WorkoutSetMilestonePolicy.moment(for: completedSet, in: exerciseSets) != nil else {
            return nil
        }
        return EncouragementGlyph.random(excludingLast: lastGlyph)
    }
}