import Core
import Foundation
import Testing
@testable import NutritionKit

@Suite("NutritionWeeklyCheckIn")
struct NutritionWeeklyCheckInTests {
    @Test("rolling window is last 7 calendar days ending asOf")
    func rollingWindow() {
        let asOf = HelmDay(year: 2026, month: 9, day: 10)
        let window = NutritionWeeklyCheckIn.rollingWindow(asOf: asOf)
        #expect(window.end == asOf)
        #expect(window.start == HelmDay(year: 2026, month: 9, day: 4))
        #expect(window.start.days(to: window.end) == 6)
    }

    @Test("isDue only on preferred weekday and not after completion")
    func isDue() {
        let sunday = HelmDay(year: 2026, month: 9, day: 6) // Sunday
        #expect(
            NutritionWeeklyCheckIn.isDue(
                today: sunday,
                todayWeekday: 1,
                preferredWeekday: 1,
                lastCompletedOn: nil
            )
        )
        #expect(
            !NutritionWeeklyCheckIn.isDue(
                today: sunday,
                todayWeekday: 1,
                preferredWeekday: 1,
                lastCompletedOn: sunday
            )
        )
        #expect(
            !NutritionWeeklyCheckIn.isDue(
                today: sunday,
                todayWeekday: 1,
                preferredWeekday: 4,
                lastCompletedOn: nil
            )
        )
        let wednesday = HelmDay(year: 2026, month: 9, day: 9)
        #expect(
            NutritionWeeklyCheckIn.isDue(
                today: wednesday,
                todayWeekday: 4,
                preferredWeekday: 4,
                lastCompletedOn: sunday
            )
        )
    }

    @Test("incomplete uses 80 percent goal and food presence")
    func incompleteRules() {
        #expect(
            NutritionWeeklyCheckIn.isIncomplete(
                loggedKcal: nil,
                goalKcal: 2_000,
                loggingComplete: false,
                hasFoodLog: false
            )
        )
        #expect(
            NutritionWeeklyCheckIn.isIncomplete(
                loggedKcal: 1_500,
                goalKcal: 2_000,
                loggingComplete: true,
                hasFoodLog: true
            )
        )
        #expect(
            !NutritionWeeklyCheckIn.isIncomplete(
                loggedKcal: 1_700,
                goalKcal: 2_000,
                loggingComplete: true,
                hasFoodLog: true
            )
        )
        #expect(
            NutritionWeeklyCheckIn.isIncomplete(
                loggedKcal: 2_000,
                goalKcal: 2_000,
                loggingComplete: false,
                hasFoodLog: true
            )
        )
    }

    @Test("default include excludes incomplete")
    func defaultInclude() {
        #expect(NutritionWeeklyCheckIn.defaultIncluded(isIncomplete: true) == false)
        #expect(NutritionWeeklyCheckIn.defaultIncluded(isIncomplete: false) == true)
    }

    @Test("confidence mirrors soft and high gates")
    func confidence() {
        #expect(NutritionWeeklyCheckIn.confidence(weighInDays: 2, foodDays: 5) == .needsData)
        #expect(NutritionWeeklyCheckIn.confidence(weighInDays: 3, foodDays: 3) == .moderate)
        #expect(NutritionWeeklyCheckIn.confidence(weighInDays: 5, foodDays: 5) == .high)
        #expect(NutritionWeeklyCheckIn.confidence(weighInDays: 5, foodDays: 4) == .moderate)
    }

    @Test("density counts only included days")
    func densityCounts() {
        let counts = NutritionWeeklyCheckIn.densityCounts(days: [
            (true, true, true),
            (true, false, true),
            (false, true, false),
            (true, true, true),
        ])
        #expect(counts.weighIns == 3)
        #expect(counts.foodDays == 2)
    }

    @Test("reconcileWeekly skips cadence stamp without enough intake days")
    func reconcileSkipsCadenceWhenSparse() {
        let asOf = HelmDay(year: 2026, month: 1, day: 14)
        var state = NutritionTrendState(
            estimatedTDEEKcal: 2_400,
            smoothedTrendWeightKg: 80,
            priorWeekTrendWeightKg: 80.2,
            lastWeeklyUpdate: HelmDay(year: 2026, month: 1, day: 10)
        )
        let days: [NutritionTrendDayInput] = (0 ..< 7).map { offset in
            NutritionTrendDayInput(
                helmDay: asOf.adding(days: offset - 6),
                bodyMassKg: 80,
                loggedIntakeKcal: 2_200
            )
        }
        let before = state.estimatedTDEEKcal
        NutritionKit.updateTrend(state: &state, weekDays: days, profileSeedTDEEKcal: 2_400)
        #expect(state.estimatedTDEEKcal == before)
        #expect(state.lastWeeklyUpdate == HelmDay(year: 2026, month: 1, day: 10))

        // Soft ritual window (7d) can update weight/intake averages but must not
        // advance cadence until intake count meets the engine minimum (10).
        NutritionKit.reconcileWeekly(state: &state, weekDays: days, profileSeedTDEEKcal: 2_400)
        #expect(state.lastWeeklyUpdate == HelmDay(year: 2026, month: 1, day: 10))
    }

    @Test("reconcileWeekly stamps cadence with enough intake days")
    func reconcileStampsCadenceWhenDense() {
        let asOf = HelmDay(year: 2026, month: 1, day: 14)
        var state = NutritionTrendState(
            estimatedTDEEKcal: 2_400,
            smoothedTrendWeightKg: 80,
            priorWeekTrendWeightKg: 80.2,
            lastWeeklyUpdate: HelmDay(year: 2026, month: 1, day: 1)
        )
        let days: [NutritionTrendDayInput] = (0 ..< 14).map { offset in
            NutritionTrendDayInput(
                helmDay: asOf.adding(days: offset - 13),
                bodyMassKg: 80,
                loggedIntakeKcal: 2_200
            )
        }
        NutritionKit.reconcileWeekly(state: &state, weekDays: days, profileSeedTDEEKcal: 2_400)
        #expect(state.lastWeeklyUpdate == asOf)
    }
}
