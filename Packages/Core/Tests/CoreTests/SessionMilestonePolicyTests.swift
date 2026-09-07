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

    @Test("skips empty workouts built as-you-go")
    func skipsManualSource() {
        #expect(SessionMilestonePolicy.applies(to: .manual) == false)
        #expect(SessionMilestonePolicy.applies(to: .healthKit) == false)
        #expect(SessionMilestonePolicy.applies(to: .prescription) == true)
        #expect(SessionMilestonePolicy.applies(to: .template) == true)
        #expect(SessionMilestonePolicy.applies(to: .importSource) == true)
    }

    @Test("toast titles stay short and ordered")
    func toastCopy() {
        #expect(SessionMilestonePolicy.toastTitle(forQuartile: 1) == "Quarter done")
        #expect(SessionMilestonePolicy.toastTitle(forQuartile: 2) == "Halfway")
        #expect(SessionMilestonePolicy.toastTitle(forQuartile: 3) == "Three quarters")
        #expect(SessionMilestonePolicy.toastTitle(forQuartile: 4) == "Nearly done")
        #expect(!SessionMilestonePolicy.toastMessage(forQuartile: 1).isEmpty)
        #expect(SessionMilestonePolicy.message(forQuartile: 1).contains("quarter"))
    }

    @Test("finish recap lists fired checkpoints")
    func finishRecap() {
        #expect(SessionMilestonePolicy.finishRecap(firedQuartiles: []) == nil)
        #expect(
            SessionMilestonePolicy.finishRecap(firedQuartiles: [1, 3])
                == "Checkpoints hit: Quarter done, Three quarters."
        )
        #expect(
            SessionMilestonePolicy.finishRecap(firedQuartiles: [4, 2, 1])
                == "Checkpoints hit: Quarter done, Halfway, Nearly done."
        )
    }
}
