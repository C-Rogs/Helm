import Core
import Foundation
import Testing
@testable import NutritionKit

@Suite("TDEECalculator")
struct TDEECalculatorTests {
    private func profile(massKg: Double = 80) -> BodyProfile {
        let calendar = Calendar(identifier: .gregorian)
        let dob = calendar.date(byAdding: .year, value: -30, to: Date())!
        return BodyProfile(
            bodyMassKg: massKg,
            heightCm: 175,
            biologicalSex: .male,
            dateOfBirth: dob
        )
    }

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
        let seedProfile = profile(massKg: 80)
        let profileSeed = try #require(BodyProfileTDEE.seedTDEEKcal(profile: seedProfile))
        var state = NutritionTrendState(estimatedTDEEKcal: 2_200)
        let maintenanceIntake = 2_800.0
        let mass = 80.0

        for week in 0 ..< 8 {
            let days = weekDays(starting: week * 7, massKg: mass, intakeKcal: maintenanceIntake)
                + weekDays(starting: week * 7 - 7, massKg: mass, intakeKcal: maintenanceIntake)
            NutritionKit.updateTrend(
                state: &state,
                weekDays: days,
                profileSeedTDEEKcal: profileSeed
            )
        }

        let estimate = try #require(state.estimatedTDEEKcal)
        #expect(abs(estimate - maintenanceIntake) < 120)
    }

    @Test("weight loss raises implied TDEE above logged intake")
    func weightLossImpliedTDEE() throws {
        let seedProfile = profile(massKg: 80)
        let profileSeed = try #require(BodyProfileTDEE.seedTDEEKcal(profile: seedProfile))
        var state = NutritionTrendState(
            estimatedTDEEKcal: 2_200,
            smoothedTrendWeightKg: 80.0,
            priorWeekTrendWeightKg: 80.5
        )

        let days = weekDays(starting: -7, massKg: 80.5, intakeKcal: 2_000)
            + weekDays(starting: 0, massKg: 80.0, intakeKcal: 2_000)
        NutritionKit.updateTrend(
            state: &state,
            weekDays: days,
            profileSeedTDEEKcal: profileSeed
        )

        let estimate = try #require(state.estimatedTDEEKcal)
        #expect(estimate > 2_000)
        #expect(estimate < 2_800)
    }

    @Test("cut logging alone does not drag TDEE below profile seed")
    func cutLoggingDoesNotCollapseTDEE() throws {
        let seedProfile = profile(massKg: 73.1)
        let profileSeed = try #require(BodyProfileTDEE.seedTDEEKcal(profile: seedProfile))
        var state = NutritionTrendState(estimatedTDEEKcal: profileSeed)

        for week in 0 ..< 4 {
            let days = weekDays(starting: week * 7, massKg: 73.1, intakeKcal: 1_850)
                + weekDays(starting: week * 7 - 7, massKg: 73.1, intakeKcal: 1_850)
            NutritionKit.updateTrend(
                state: &state,
                weekDays: days,
                profileSeedTDEEKcal: profileSeed
            )
        }

        let estimate = try #require(state.estimatedTDEEKcal)
        #expect(estimate >= profileSeed * 0.85)
    }
    @Test("same evidence is idempotent and updates only after cadence")
    func cadenceAndIdempotence() throws {
        let days = weekDays(starting: 0, massKg: 80, intakeKcal: 2_800)
            + weekDays(starting: 7, massKg: 80, intakeKcal: 2_800)
        var state = NutritionTrendState(estimatedTDEEKcal: 2_200, priorWeekTrendWeightKg: 80)

        NutritionKit.updateTrend(state: &state, weekDays: days, profileSeedTDEEKcal: 2_200)
        let first = state
        NutritionKit.updateTrend(state: &state, weekDays: days, profileSeedTDEEKcal: 2_200)

        #expect(state == first)
        #expect(state.lastWeeklyUpdate == days.last?.helmDay)
    }

    @Test("insufficient evidence does not adapt estimate")
    func requiresLongerEvidenceWindow() {
        let days = weekDays(starting: 0, massKg: 80, intakeKcal: 3_000)
        var state = NutritionTrendState(estimatedTDEEKcal: 2_200, priorWeekTrendWeightKg: 80)

        NutritionKit.updateTrend(state: &state, weekDays: days, profileSeedTDEEKcal: 2_200)

        #expect(state.estimatedTDEEKcal == 2_200)
    }

}
