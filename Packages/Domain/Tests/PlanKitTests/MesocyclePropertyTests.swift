import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Mesocycle property tests")
struct MesocyclePropertyTests {
    @Test("weekly targets never exceed MRV outside deload")
    func volumeNeverExceedsMRV() {
        for blockLength in 4 ... 6 {
            for mev in 4 ... 12 {
                for mrv in (mev + 1) ... (mev + 15) {
                    let landmarks = VolumeLandmarks(mev: mev, mrv: mrv)
                    for week in 1 ..< blockLength {
                        let target = MesocycleEngine.accumulatingTarget(
                            week: week,
                            landmarks: landmarks,
                            blockLength: blockLength
                        )
                        #expect(target <= mrv)
                        #expect(target >= mev)
                    }
                }
            }
        }
    }

    @Test("accumulating weeks ramp monotonically toward MRV")
    func monotoneAccumulation() {
        for blockLength in 4 ... 6 {
            let landmarks = VolumeLandmarks(mev: 8, mrv: 18)
            var previous = 0
            for week in 1 ..< blockLength {
                let target = MesocycleEngine.accumulatingTarget(
                    week: week,
                    landmarks: landmarks,
                    blockLength: blockLength
                )
                #expect(target >= previous)
                previous = target
            }
        }
    }

    @Test("deload target never drops below MEV even when half peak is lower")
    func deloadNeverBelowMEV() {
        let landmarks = VolumeLandmarks(mev: 10, mrv: 12)
        let target = PlanKit.deloadWeeklyTarget(landmarks: landmarks, blockLength: 4)
        #expect(target == landmarks.mev)
    }

    @Test("deload week is strictly lighter than the peak accumulating week")
    func deloadInvariants() {
        for blockLength in 4 ... 6 {
            let landmarks = VolumeLandmarks(mev: 8, mrv: 20)
            let muscleState = MuscleMesocycleState(
                landmarks: landmarks,
                blockLengthWeeks: blockLength,
                currentWeek: blockLength
            )
            let peakWeek = blockLength - 1
            let peak = MesocycleEngine.accumulatingTarget(
                week: peakWeek,
                landmarks: landmarks,
                blockLength: blockLength
            )
            let deload = PlanKit.weeklyHardSetTarget(for: muscleState)

            #expect(muscleState.phase == .deload)
            #expect(deload < peak)
            #expect(deload >= landmarks.mev)
        }
    }

    @Test("advancing through a full block ends on deload then resets to week one")
    func fullBlockCycle() {
        var state = PlanKit.makeInitialState(
            muscles: [.chest, .back],
            experience: .intermediate,
            blockLengthWeeks: 5
        )

        for expectedWeek in 2 ... 5 {
            state = PlanKit.advanceWeek(state)
            for muscle in [MuscleGroup.chest, .back] {
                #expect(state.muscles[muscle]?.currentWeek == expectedWeek)
            }
        }

        #expect(state.muscles[.chest]?.phase == .deload)

        let preResetLandmarks = state.muscles[.chest]!.landmarks
        state = PlanKit.advanceWeek(
            state,
            toleranceByMuscle: [
                .chest: ToleranceSignals(averageRIR: 3, sorenessRating: 2, performanceTrend: .improving)
            ]
        )

        #expect(state.muscles[.chest]?.currentWeek == 1)
        #expect(state.muscles[.chest]?.phase == .accumulating)
        let refinedMRV = state.muscles[.chest]?.landmarks.mrv ?? 0
        #expect(refinedMRV >= preResetLandmarks.mrv)
    }

    @Test("every muscle in initial state starts at week one accumulating")
    func initialStateShape() {
        let state = PlanKit.makeInitialState(
            muscles: MuscleGroup.allCases,
            experience: .novice,
            blockLengthWeeks: 4
        )
        for muscle in MuscleGroup.allCases {
            let muscleState = state.muscles[muscle]
            #expect(muscleState?.currentWeek == 1)
            #expect(muscleState?.phase == .accumulating)
            #expect(PlanKit.weeklyHardSetTarget(for: muscleState!) == muscleState?.landmarks.mev)
        }
    }
}

@Suite("Landmark seeding and refinement")
struct LandmarkTests {
    @Test("advanced experience yields higher landmarks than novice")
    func experienceScaling() {
        for muscle in MuscleGroup.allCases {
            let novice = PlanKit.seedLandmarks(muscle: muscle, experience: .novice)
            let advanced = PlanKit.seedLandmarks(muscle: muscle, experience: .advanced)
            #expect(advanced.mrv >= novice.mrv)
            #expect(advanced.mev >= novice.mev)
        }
    }

    @Test("declining performance pulls MRV down")
    func decliningRefinement() {
        let landmarks = VolumeLandmarks(mev: 8, mrv: 18)
        let refined = PlanKit.refineLandmarks(
            landmarks,
            signals: ToleranceSignals(sorenessRating: 8, performanceTrend: .declining)
        )
        #expect(refined.mrv < landmarks.mrv)
        #expect(refined.mev == landmarks.mev)
    }
}
