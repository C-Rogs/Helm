import Core
import Foundation
import Testing
@testable import NutritionKit

@Suite("Macro targets")
struct MacroTargetTests {
    private func targets(
        phase: TrainingPhase,
        weeklyRateKg: Double? = nil,
        bodyMassKg: Double = 80,
        dayType: NutritionDayType = .training,
        trendTDEE: Double? = nil
    ) -> MacroTargets {
        let trend = NutritionTrendState(estimatedTDEEKcal: trendTDEE)
        return NutritionKit.targets(
            for: NutritionTargetContext(bodyMassKg: bodyMassKg, dayType: dayType),
            phase: PhaseGoal(phase: phase, weeklyRateKg: weeklyRateKg),
            trend: trend
        )
    }

    @Test("phase shifts calorie target")
    func phaseShift() {
        let cut = targets(phase: .cut, trendTDEE: 2_640)
        let gain = targets(phase: .gain, trendTDEE: 2_640)

        #expect(cut.caloriesKcal < gain.caloriesKcal)
        #expect(cut.proteinGrams == 160)
    }

    @Test("training day allocates more carbs than rest day")
    func dayTypePeriodisation() {
        let training = targets(phase: .maintain, bodyMassKg: 75, dayType: .training, trendTDEE: 2_475)
        let rest = targets(phase: .maintain, bodyMassKg: 75, dayType: .rest, trendTDEE: 2_475)

        #expect(training.carbohydrateGrams > rest.carbohydrateGrams)
        #expect(training.dayType == .training)
        #expect(rest.dayType == .rest)
    }

    @Test("deload day uses rest-like carb share")
    func deloadPeriodisation() {
        let deload = targets(phase: .maintain, bodyMassKg: 75, dayType: .deload, trendTDEE: 2_475)
        let rest = targets(phase: .maintain, bodyMassKg: 75, dayType: .rest, trendTDEE: 2_475)

        #expect(deload.carbohydrateGrams == rest.carbohydrateGrams)
    }

    @Test("custom weekly rate adjusts deficit")
    func weeklyRate() {
        let defaultCut = targets(phase: .cut, trendTDEE: 3_000)
        let aggressiveCut = targets(phase: .cut, weeklyRateKg: 0.75, trendTDEE: 3_000)

        #expect(aggressiveCut.caloriesKcal < defaultCut.caloriesKcal)
    }

    @Test("invalid weekly rates use deterministic defaults")
    func invalidWeeklyRates() {
        let defaultCut = targets(phase: .cut, trendTDEE: 3_000)
        #expect(targets(phase: .cut, weeklyRateKg: -0.5, trendTDEE: 3_000) == defaultCut)
        #expect(targets(phase: .cut, weeklyRateKg: .infinity, trendTDEE: 3_000) == defaultCut)
    }

    @Test("fat floor is retained and macro calories reconcile")
    func fatFloorAndRounding() {
        let result = targets(phase: .cut, weeklyRateKg: 1, bodyMassKg: 100, trendTDEE: 2_000)
        let macroCalories = result.proteinGrams * 4 + result.carbohydrateGrams * 4 + result.fatGrams * 9

        #expect(result.fatGrams >= 60)
        #expect(result.caloriesKcal == macroCalories)
    }

    @Test("profile seeds macro targets from Mifflin-St Jeor maintenance")
    func profileSeedTargets() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dob = calendar.date(byAdding: .year, value: -30, to: Date())!
        let profile = BodyProfile(
            bodyMassKg: 73.1,
            heightCm: 175,
            biologicalSex: .male,
            dateOfBirth: dob
        )
        let profileSeed = try #require(BodyProfileTDEE.seedTDEEKcal(profile: profile))
        let targets = NutritionKit.targets(
            for: NutritionTargetContext(bodyProfile: profile, dayType: .training),
            phase: PhaseGoal(phase: .maintain),
            trend: NutritionTrendState()
        )

        #expect(targets.estimatedTDEEKcal == Int(profileSeed.rounded()))
        #expect(targets.caloriesKcal == targets.estimatedTDEEKcal)
    }

    func coldStartCalorieTarget() {
        let targets = NutritionKit.targets(
            for: NutritionTargetContext(bodyMassKg: 0, dayType: .training),
            phase: PhaseGoal(phase: .maintain),
            trend: NutritionTrendState(estimatedTDEEKcal: 0)
        )

        #expect(targets.caloriesKcal == 0)
        #expect(targets.proteinGrams == 0)
    }
}
