import Foundation
import Testing
@testable import Core

@Suite("Session milestone policy")
struct SessionMilestonePolicyTests {
    @Test("fires at most four quartiles")
    func firesQuartilesOnce() {
        var fired: Set<Int> = []
        var previous = 0
        let total = 20
        var messages: [Int] = []
        for completed in 1...20 {
            if let q = SessionMilestonePolicy.crossedMilestone(
                previousCompleted: previous,
                completed: completed,
                total: total,
                alreadyFiredQuartiles: fired
            ) {
                messages.append(q)
                fired.insert(q)
            }
            previous = completed
        }
        #expect(messages == [1, 2, 3, 4])
        #expect(fired.count == 4)
    }

    @Test("skips when toggle would have already fired quartile")
    func skipsDuplicate() {
        let q = SessionMilestonePolicy.crossedMilestone(
            previousCompleted: 4,
            completed: 5,
            total: 20,
            alreadyFiredQuartiles: [1]
        )
        #expect(q == nil)
    }

    @Test("respects max fires")
    func maxFires() {
        let q = SessionMilestonePolicy.crossedMilestone(
            previousCompleted: 14,
            completed: 15,
            total: 20,
            alreadyFiredQuartiles: [1, 2, 3, 4]
        )
        #expect(q == nil)
    }
}
