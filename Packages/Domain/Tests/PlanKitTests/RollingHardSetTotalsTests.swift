import Core
import Foundation
import PlanKit
import Testing

@Suite("Rolling hard-set totals")
struct RollingHardSetTotalsTests {
    private let chestMap = ExerciseMuscleMap(
        exerciseID: "bench",
        contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0)]
    )

    private func session(day: HelmDay) -> WorkoutSession {
        WorkoutSession(
            helmDay: day,
            startedAt: Date(),
            sets: [
                LoggedSet(
                    exerciseID: "bench",
                    sequence: 1,
                    reps: 8,
                    completedAt: Date(),
                    isWarmup: false
                )
            ]
        )
    }

    @Test("rolling window includes only the last seven days")
    func rollingWindowBoundary() {
        let endDay = HelmDay(year: 2026, month: 7, day: 31)
        let insideWindow = HelmDay(year: 2026, month: 7, day: 26)
        let outsideWindow = HelmDay(year: 2026, month: 7, day: 24)

        let ledger = PlanKit.rollingHardSetTotals(
            sessions: [session(day: insideWindow), session(day: outsideWindow)],
            muscleMaps: ["bench": chestMap],
            endingAt: endDay
        )

        #expect(ledger.weekStart == HelmDay(year: 2026, month: 7, day: 25))
        #expect(ledger.totals[.chest] == 1)
    }

    @Test("rolling window differs from calendar week start")
    func rollingVersusCalendarWeek() {
        let endDay = HelmDay(year: 2026, month: 7, day: 31) // Thursday
        let fridayBeforeWeek = HelmDay(year: 2026, month: 7, day: 25)
        let mondayWeekStart = HelmDay(year: 2026, month: 7, day: 28)

        let sessions = [session(day: fridayBeforeWeek)]
        let rolling = PlanKit.rollingHardSetTotals(
            sessions: sessions,
            muscleMaps: ["bench": chestMap],
            endingAt: endDay
        )
        let calendarWeek = PlanKit.weeklyHardSetTotals(
            sessions: sessions,
            muscleMaps: ["bench": chestMap],
            weekStart: mondayWeekStart
        )

        #expect(rolling.totals[MuscleGroup.chest] == 1)
        #expect(calendarWeek.totals[MuscleGroup.chest] == nil)
        #expect(rolling.weekStart == HelmDay(year: 2026, month: 7, day: 25))
        #expect(mondayWeekStart == HelmDay(year: 2026, month: 7, day: 28))
    }
}
