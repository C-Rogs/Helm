import Foundation

/// First / mid / last working-set moments within one exercise (non-PR encouragement).
public enum WorkoutSetMilestonePolicy {
    public enum Moment: Equatable, Sendable {
        case first
        case middle
        case last
    }

    public static func moment(
        for completedSet: SetEntryDraft,
        in exerciseSets: [SetEntryDraft]
    ) -> Moment? {
        guard completedSet.status == .completed, !completedSet.setType.isWarmup else { return nil }

        let workingSets = exerciseSets.filter { !$0.setType.isWarmup }
        guard !workingSets.isEmpty,
              let index = workingSets.firstIndex(where: { $0.id == completedSet.id }) else {
            return nil
        }

        let count = workingSets.count
        let middleIndex = Int((Double(count - 1) / 2.0).rounded())
        if index == 0 { return .first }
        if index == count - 1 { return .last }
        if index == middleIndex { return .middle }
        return nil
    }
}