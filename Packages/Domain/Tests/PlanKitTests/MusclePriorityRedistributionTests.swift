import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Muscle priority redistribution")
struct MusclePriorityRedistributionTests {
    @Test("empty priorities leave targets unchanged")
    func emptyPrioritiesIdentity() {
        let state = PlanKit.makeInitialState(
            muscles: [.chest, .back, .quads],
            experience: .intermediate,
            blockLengthWeeks: 5
        )
        let base = PlanKit.weeklyHardSetTargets(for: state, priorities: [])
        let again = PlanKit.weeklyHardSetTargets(for: state, priorities: [])
        #expect(base == again)
        for (muscle, muscleState) in state.muscles {
            #expect(base[muscle] == PlanKit.weeklyHardSetTarget(for: muscleState))
        }
    }

    @Test("priority muscle gains sets; non-priority shrinks")
    func priorityBoostAndNonPriorityShrink() {
        let state = PlanKit.makeInitialState(
            muscles: [.chest, .back, .quads, .hamstrings],
            experience: .intermediate,
            blockLengthWeeks: 5
        )
        // Mid-block so base > MEV and there is room to boost/shrink.
        var mid = state
        for muscle in mid.muscles.keys {
            var muscleState = mid.muscles[muscle]!
            muscleState.currentWeek = 3
            mid.muscles[muscle] = muscleState
        }

        let base = PlanKit.weeklyHardSetTargets(for: mid, priorities: [])
        let prioritized = PlanKit.weeklyHardSetTargets(for: mid, priorities: [.chest])

        #expect(prioritized[.chest]! > base[.chest]!)
        #expect(prioritized[.back]! <= base[.back]!)
        #expect(prioritized[.quads]! <= base[.quads]!)
        #expect(prioritized[.hamstrings]! <= base[.hamstrings]!)

        let baseTotal = base.values.reduce(0, +)
        let priTotal = prioritized.values.reduce(0, +)
        // Total stays similar; MEV floors may leave a small residual surplus.
        #expect(priTotal <= baseTotal + 3)
        #expect(priTotal >= baseTotal - 1)
    }

    @Test("multiple priorities each boost; others shrink")
    func multiplePriorities() {
        let state = PlanKit.makeInitialState(
            muscles: MuscleGroup.allCases,
            experience: .intermediate,
            blockLengthWeeks: 5
        )
        var mid = state
        for muscle in mid.muscles.keys {
            var muscleState = mid.muscles[muscle]!
            muscleState.currentWeek = 3
            mid.muscles[muscle] = muscleState
        }

        let base = PlanKit.weeklyHardSetTargets(for: mid, priorities: [])
        let focus: [MuscleGroup] = [.chest, .back, .shoulders]
        let prioritized = PlanKit.weeklyHardSetTargets(for: mid, priorities: focus)

        for muscle in focus {
            #expect(prioritized[muscle]! >= base[muscle]!)
        }
        for muscle in MuscleGroup.allCases where !focus.contains(muscle) {
            #expect(prioritized[muscle]! <= base[muscle]!)
        }
    }

    @Test("priorities clamped to MEV-MRV")
    func landmarkClamp() {
        var state = MesocycleState()
        state.muscles[.chest] = MuscleMesocycleState(
            landmarks: VolumeLandmarks(mev: 10, mrv: 11),
            blockLengthWeeks: 5,
            currentWeek: 4
        )
        state.muscles[.back] = MuscleMesocycleState(
            landmarks: VolumeLandmarks(mev: 8, mrv: 20),
            blockLengthWeeks: 5,
            currentWeek: 4
        )
        let prioritized = PlanKit.weeklyHardSetTargets(for: state, priorities: [.chest])
        #expect(prioritized[.chest]! <= 11)
        #expect(prioritized[.chest]! >= 10)
        #expect(prioritized[.back]! >= 8)
    }

    @Test("more than three priorities are truncated")
    func capThree() {
        let raw = MusclePriorityRedistribution.normalize([
            .chest, .back, .shoulders, .biceps, .triceps
        ])
        #expect(raw == [.chest, .back, .shoulders])
    }

    @Test("PhaseGoal resolves raw priority strings")
    func phaseGoalResolution() {
        let goal = PhaseGoal(
            phase: .gain,
            musclePriorities: ["Chest", "back", "back", "quads", "calves", "nope"]
        )
        #expect(goal.musclePriorities == ["chest", "back", "quads"])
        #expect(goal.resolvedMusclePriorities == [.chest, .back, .quads])
        #expect(goal.musclePrioritiesDisplayLabel == "Chest · Back · Quads")
    }
}
