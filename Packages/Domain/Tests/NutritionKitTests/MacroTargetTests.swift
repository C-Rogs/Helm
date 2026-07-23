import Core
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
}
