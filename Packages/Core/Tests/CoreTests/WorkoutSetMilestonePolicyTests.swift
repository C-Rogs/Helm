import Foundation
import Testing
@testable import Core

@Suite("Workout set milestone policy")
struct WorkoutSetMilestonePolicyTests {
    @Test("marks first middle and last working sets")
    func marksBookendsAndMiddle() {
        let sets = [
            SetEntryDraft(id: "w0", setIndex: 0, setType: .warmup, status: .completed),
            SetEntryDraft(id: "a", setIndex: 1, status: .completed),
            SetEntryDraft(id: "b", setIndex: 2, status: .completed),
            SetEntryDraft(id: "c", setIndex: 3, status: .completed),
            SetEntryDraft(id: "d", setIndex: 4, status: .completed),
        ]

        #expect(WorkoutSetMilestonePolicy.moment(for: sets[0], in: sets) == nil)
        #expect(WorkoutSetMilestonePolicy.moment(for: sets[1], in: sets) == .first)
        #expect(WorkoutSetMilestonePolicy.moment(for: sets[2], in: sets) == nil)
        #expect(WorkoutSetMilestonePolicy.moment(for: sets[3], in: sets) == .middle)
        #expect(WorkoutSetMilestonePolicy.moment(for: sets[4], in: sets) == .last)
    }
}
