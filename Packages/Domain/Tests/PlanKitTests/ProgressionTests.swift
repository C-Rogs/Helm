import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Lift progression")
struct ProgressionTests {
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

    @Test("Epley e1RM matches hand calculation")
    func epleyFormula() {
        let e1rm = PlanKit.estimatedOneRepMax(mass: Mass(kilograms: 100), reps: 10)
        #expect(abs(e1rm.kilograms - 133.333) < 0.01)
    }

    @Test("progression bumps weight after hitting top of rep range with spare RIR")
    func weightBumpOnSuccess() {
        let history = [
            set(exerciseID: "bench_press", kg: 80, reps: 12, rir: 2, at: 0),
            set(exerciseID: "bench_press", kg: 80, reps: 12, rir: 2, at: 1),
            set(exerciseID: "bench_press", kg: 80, reps: 12, rir: 2, at: 2)
        ]

        let progression = PlanKit.progression(for: "bench_press", history: history)
        #expect(progression.workingWeight!.kilograms > 80)
        #expect(progression.estimatedOneRepMax != nil)
    }

    @Test("progression holds weight when reps fall short")
    func holdWeightWhenShort() {
        let history = [
            set(exerciseID: "squat", kg: 120, reps: 8, rir: 1, at: 0),
            set(exerciseID: "squat", kg: 120, reps: 9, rir: 1, at: 1)
        ]

        let progression = PlanKit.progression(for: "squat", history: history)
        #expect(progression.workingWeight!.kilograms == 120)
    }

    @Test("warmup sets are ignored for progression")
    func ignoresWarmups() {
        let warmup = LoggedSet(
            exerciseID: "row",
            sequence: 0,
            mass: Mass(kilograms: 40),
            reps: 15,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isWarmup: true
        )
        let working = set(exerciseID: "row", kg: 70, reps: 10, at: 1)
        let progression = PlanKit.progression(for: "row", history: [warmup, working])

        #expect(progression.workingWeight!.kilograms == 70)
        #expect(progression.estimatedOneRepMax!.kilograms > 70)
    }
}

@Suite("Weekly hard-set accounting")
struct HardSetAccountingTests {
    @Test("fractional muscle credit sums correctly")
    func fractionalCredit() {
        let map = ExerciseMuscleMap(
            exerciseID: "incline_press",
            contributions: [
                ExerciseMuscleContribution(muscle: .chest, fraction: 0.7),
                ExerciseMuscleContribution(muscle: .shoulders, fraction: 0.3)
            ]
        )

        let session = WorkoutSession(
            helmDay: HelmDay(year: 2026, month: 3, day: 10),
            startedAt: Date(),
            sets: [
                LoggedSet(
                    exerciseID: "incline_press",
                    sequence: 1,
                    reps: 10,
                    completedAt: Date(),
                    isWarmup: false
                ),
                LoggedSet(
                    exerciseID: "incline_press",
                    sequence: 2,
                    reps: 10,
                    completedAt: Date(),
                    isWarmup: false
                )
            ]
        )

        let ledger = PlanKit.weeklyHardSetTotals(
            sessions: [session],
            muscleMaps: ["incline_press": map],
            weekStart: HelmDay(year: 2026, month: 3, day: 10)
        )

        #expect(ledger.totals[.chest] == 1.4)
        #expect(ledger.totals[.shoulders] == 0.6)
    }

    @Test("warmup sets do not count toward weekly volume")
    func warmupsExcluded() {
        let map = ExerciseMuscleMap(
            exerciseID: "curl",
            contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1.0)]
        )
        let session = WorkoutSession(
            helmDay: HelmDay(year: 2026, month: 3, day: 10),
            startedAt: Date(),
            sets: [
                LoggedSet(
                    exerciseID: "curl",
                    sequence: 0,
                    reps: 12,
                    completedAt: Date(),
                    isWarmup: true
                )
            ]
        )

        let ledger = PlanKit.weeklyHardSetTotals(
            sessions: [session],
            muscleMaps: ["curl": map],
            weekStart: HelmDay(year: 2026, month: 3, day: 10)
        )

        #expect(ledger.totals[.biceps] == nil)
    }
}
