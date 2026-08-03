import Core
import Foundation
import Testing
@testable import NutritionKit

@Suite("TrendWeightSmoother")
struct TrendWeightSmootherTests {
    @Test("stable series: robust EWMA matches plain EWMA")
    func stableSeriesUnchanged() throws {
        let values = [80.0, 80.1, 79.9, 80.0, 80.05, 79.95, 80.0, 80.1, 79.9, 80.0]
        let plain = TrendWeightSmoother.ewma(values)
        let robust = TrendWeightSmoother.robustEwma(values)
        let plainValue = try #require(plain)
        let robustValue = try #require(robust)
        #expect(abs(plainValue - robustValue) < 0.01)
    }

    @Test("all-equal series unchanged by Hampel")
    func allEqualPassesThrough() {
        let values = Array(repeating: 80.0, count: 10)
        let filtered = TrendWeightSmoother.hampelFilter(values)
        #expect(filtered == values)
        #expect(TrendWeightSmoother.robustEwma(values) == 80.0)
    }

    @Test("single water spike is replaced before EWMA")
    func spikeRejectedBeforeEWMA() throws {
        // Flat ~80 kg with one +2 kg sodium/refeed spike.
        var values = Array(repeating: 80.0, count: 14)
        values[7] = 82.0

        let filtered = TrendWeightSmoother.hampelFilter(values)
        #expect(abs(filtered[7] - 80.0) < 0.01)

        let rawEwma = try #require(TrendWeightSmoother.ewma(values))
        let robustEwma = try #require(TrendWeightSmoother.robustEwma(values))
        // Robust trend stays closer to 80 than raw EWMA after the spike.
        #expect(abs(robustEwma - 80.0) < abs(rawEwma - 80.0))
        #expect(abs(robustEwma - 80.0) < 0.15)
    }

    @Test("updateTrend ignores transient spike vs prior week")
    func updateTrendSpikeDoesNotFakeWeightLoss() throws {
        let calendar = Calendar(identifier: .gregorian)
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        func days(offset: Int, masses: [Double], intake: Double) -> [NutritionTrendDayInput] {
            masses.enumerated().map { index, mass in
                let date = calendar.date(byAdding: .day, value: offset + index, to: anchor)!
                return NutritionTrendDayInput(
                    helmDay: HelmDay.day(for: date, calendar: calendar),
                    bodyMassKg: mass,
                    loggedIntakeKcal: intake
                )
            }
        }

        var state = NutritionTrendState(
            estimatedTDEEKcal: 2_500,
            smoothedTrendWeightKg: 80.0,
            priorWeekTrendWeightKg: 80.0
        )

        // Prior week: stable 80 kg.
        let priorWeek = days(offset: 0, masses: Array(repeating: 80.0, count: 7), intake: 2_500)
        NutritionKit.updateTrend(
            state: &state,
            weekDays: priorWeek,
            profileSeedTDEEKcal: 2_500
        )
        let priorTrend = try #require(state.smoothedTrendWeightKg)
        #expect(abs(priorTrend - 80.0) < 0.05)

        // Current week: mostly 80 with one +2 kg spike (not real fat gain).
        var spiked = Array(repeating: 80.0, count: 7)
        spiked[3] = 82.0
        let currentWeek = days(offset: 7, masses: spiked, intake: 2_500)
        NutritionKit.updateTrend(
            state: &state,
            weekDays: currentWeek,
            profileSeedTDEEKcal: 2_500
        )

        let currentTrend = try #require(state.smoothedTrendWeightKg)
        // Without Hampel, EWMA would lift trend and imply false weight gain / lower TDEE.
        #expect(abs(currentTrend - priorTrend) < 0.2)

        let estimate = try #require(state.estimatedTDEEKcal)
        #expect(estimate >= 2_400)
        #expect(estimate <= 2_600)
    }
}
