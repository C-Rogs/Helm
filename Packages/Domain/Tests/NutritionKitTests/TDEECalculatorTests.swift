import Core
import Foundation
import Testing
@testable import NutritionKit

@Suite("TDEECalculator")
struct TDEECalculatorTests {
    private func weekDays(
        starting offset: Int,
        massKg: Double,
        intakeKcal: Double
    ) -> [NutritionTrendDayInput] {
        let calendar = Calendar(identifier: .gregorian)
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        return (0 ..< 7).map { dayOffset in
            let date = calendar.date(byAdding: .day, value: offset + dayOffset, to: anchor)!
            return NutritionTrendDayInput(
                helmDay: HelmDay.day(for: date, calendar: calendar),
                bodyMassKg: massKg,
                loggedIntakeKcal: intakeKcal
            )
        }
    }

    @Test("TDEE converges toward maintenance intake on stable weight")
    func stableWeightConvergence() throws {
        var state = NutritionTrendState(estimatedTDEEKcal: 2_200)
        let maintenanceIntake = 2_800.0
        let mass = 80.0

        for week in 0 ..< 8 {
            let days = weekDays(starting: week * 7, massKg: mass, intakeKcal: maintenanceIntake)
            NutritionKit.updateTrend(state: &state, weekDays: days)
        }

        let estimate = try #require(state.estimatedTDEEKcal)
        #expect(abs(estimate - maintenanceIntake) < 120)
    }

    @Test("weight loss raises implied TDEE above logged intake")
    func weightLossImpliedTDEE() throws {
        var state = NutritionTrendState(
            estimatedTDEEKcal: 2_200,
            smoothedTrendWeightKg: 80.0,
            priorWeekTrendWeightKg: 80.5
        )

        let days = weekDays(starting: 0, massKg: 80.0, intakeKcal: 2_000)
        NutritionKit.updateTrend(state: &state, weekDays: days)

        let estimate = try #require(state.estimatedTDEEKcal)
        #expect(estimate > 2_000)
        #expect(estimate < 2_800)
    }
}
