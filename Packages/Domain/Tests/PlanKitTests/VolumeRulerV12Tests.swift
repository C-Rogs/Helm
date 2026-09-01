import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Progression by lift kind")
struct ProgressionByLiftTests {
    private func set(
        exerciseID: String,
        kg: Double,
        reps: Int,
        rir: Int? = 2,
        at offset: TimeInterval = 0
    ) -> LoggedSet {
        LoggedSet(
            exerciseID: exerciseID,
            sequence: 1,
            mass: Mass(kilograms: kg),
            reps: reps,
            rir: rir,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            isWarmup: false
        )
    }

    @Test("compounds use load-first rep range and wider weight bump")
    func compoundProgression() {
        let history = [
            set(exerciseID: "bench_press", kg: 80, reps: 12, rir: 2, at: 0),
            set(exerciseID: "bench_press", kg: 80, reps: 12, rir: 2, at: 1)
        ]
        let progression = PlanKit.progression(for: "bench_press", history: history)
        #expect(progression.targetRepMin == 8)
        #expect(progression.targetRepMax == 8)
        #expect(progression.schemeRepMin == 8)
        #expect(progression.schemeRepMax == 12)
        #expect(progression.workingWeight!.kilograms > 80)
    }

    @Test("isolation uses higher rep range and smaller bump")
    func isolationProgression() {
        let map = ExerciseMuscleMap(
            exerciseID: "dumbbell_curl",
            contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1.0, tier: .primary)]
        )
        let history = [
            set(exerciseID: "dumbbell_curl", kg: 12, reps: 15, rir: 2, at: 0),
            set(exerciseID: "dumbbell_curl", kg: 12, reps: 15, rir: 1, at: 0.5)
        ]
        let progression = PlanKit.progression(for: "dumbbell_curl", history: history, muscleMap: map)
        #expect(progression.targetRepMin == 10)
        #expect(progression.targetRepMax == 10)
        #expect(progression.schemeRepMin == 10)
        #expect(progression.schemeRepMax == 15)
        // The old percentage bump asked for 0.3 kg on a 12 kg dumbbell, which does not exist.
        // Isolation now steps to the next real dumbbell, and that step stays smaller than
        // the barbell step a compound gets.
        let bump = progression.workingWeight!.kilograms - 12
        #expect(bump == LoadIncrement.dumbbell.stepKilograms)
        #expect(LoadIncrement.dumbbell.stepKilograms < LoadIncrement.barbell.stepKilograms)
    }

    @Test("prescribed loads are always loadable")
    func progressionSnapsToLoadableWeight() {
        let history = [
            set(exerciseID: "bench_press", kg: 82.5, reps: 12, rir: 2, at: 0),
            set(exerciseID: "bench_press", kg: 82.5, reps: 12, rir: 2, at: 1)
        ]
        let progression = PlanKit.progression(for: "bench_press", history: history)
        let kilograms = progression.workingWeight!.kilograms
        let step = LoadIncrement.barbell.stepKilograms
        #expect(abs((kilograms / step).rounded() * step - kilograms) < 0.0001)
        #expect(kilograms > 82.5)
    }
}

@Suite("V_base historical seeding")
struct VBaseSeedingTests {
    @Test("historical weekly average lifts landmarks on new block seed")
    func historicalSeeding() {
        let experienceOnly = PlanKit.seedLandmarks(muscle: .back, experience: .intermediate)
        let withHistory = PlanKit.seedLandmarks(
            muscle: .back,
            experience: .intermediate,
            historicalWeeklyHardSets: 16
        )
        #expect(withHistory.mev >= experienceOnly.mev)
        #expect(withHistory.mrv >= experienceOnly.mrv)
    }

    @Test("empty history keeps experience scalars")
    func emptyHistoryFallsBack() {
        let baseline = PlanKit.seedLandmarks(muscle: .chest, experience: .novice)
        let same = PlanKit.seedLandmarks(
            muscle: .chest,
            experience: .novice,
            historicalWeeklyHardSets: nil
        )
        #expect(same == baseline)
    }
}
