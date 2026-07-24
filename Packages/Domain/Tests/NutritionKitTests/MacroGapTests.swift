import Core
import Testing
@testable import NutritionKit

@Suite("Macro gap")
struct MacroGapTests {
    private let day = HelmDay(year: 2026, month: 7, day: 23)

    @Test("detects alcohol-heavy untracked energy")
    func alcoholGap() {
        let nutritionDay = NutritionDay(
            helmDay: day,
            totalEnergy: Energy(kilocalories: 600),
            totalProteinGrams: 4,
            totalCarbohydrateGrams: 30,
            totalFatGrams: 0
        )

        let gap = MacroGapCalculator.macroGap(for: nutritionDay)
        #expect(gap != nil)
        #expect(gap! > 100)
    }

    @Test("explicit alcohol kcal is subtracted from macro gap")
    func explicitAlcoholSubtracted() {
        let gap = MacroGapCalculator.macroGap(
            totalEnergyKcal: 420,
            proteinGrams: 4,
            carbohydrateGrams: 34,
            fatGrams: 0,
            explicitAlcoholKilocalories: 420
        )

        #expect(gap == nil)
    }

    @Test("alcohol day does not distort carb and fat targets")
    func gapDoesNotDistortTargets() {
        let alcoholDay = NutritionDay(
            helmDay: day,
            totalEnergy: Energy(kilocalories: 2_400),
            totalProteinGrams: 150,
            totalCarbohydrateGrams: 400,
            totalFatGrams: 20
        )

        let baseline = NutritionKit.targets(
            for: NutritionTargetContext(bodyMassKg: 80, dayType: .training),
            phase: PhaseGoal(phase: .maintain),
            trend: NutritionTrendState(estimatedTDEEKcal: 2_640)
        )

        let withLoggedDay = NutritionKit.targets(
            for: NutritionTargetContext(bodyMassKg: 80, dayType: .training, loggedDay: alcoholDay),
            phase: PhaseGoal(phase: .maintain),
            trend: NutritionTrendState(estimatedTDEEKcal: 2_640)
        )

        #expect(withLoggedDay.macroGapKilocalories != nil)
        #expect(withLoggedDay.carbohydrateGrams == baseline.carbohydrateGrams)
        #expect(withLoggedDay.fatGrams == baseline.fatGrams)
        #expect(withLoggedDay.caloriesKcal == baseline.caloriesKcal)
    }
}
