import Core
import Foundation

public enum MacroGapCalculator {
    public static let significanceThresholdKcal = 1.0

    public static func reconstructedEnergyKcal(
        proteinGrams: Double,
        carbohydrateGrams: Double,
        fatGrams: Double
    ) -> Double {
        proteinGrams * 4 + carbohydrateGrams * 4 + fatGrams * 9
    }

    public static func macroGap(
        totalEnergyKcal: Double,
        proteinGrams: Double,
        carbohydrateGrams: Double,
        fatGrams: Double,
        explicitAlcoholKilocalories: Double = 0
    ) -> Double? {
        let reconstructed = reconstructedEnergyKcal(
            proteinGrams: proteinGrams,
            carbohydrateGrams: carbohydrateGrams,
            fatGrams: fatGrams
        )
        let gap = totalEnergyKcal - reconstructed - explicitAlcoholKilocalories
        return gap > significanceThresholdKcal ? gap : nil
    }

    public static func explicitAlcoholKilocalories(from meals: [MealRecord]) -> Double {
        meals
            .filter { $0.source == .alcohol }
            .compactMap(\.energy?.kilocalories)
            .reduce(0, +)
    }

    public static func macroGap(for day: NutritionDay) -> Double? {
        guard
            let totalEnergy = day.totalEnergy?.kilocalories,
            let protein = day.totalProteinGrams,
            let carbs = day.totalCarbohydrateGrams,
            let fat = day.totalFatGrams
        else {
            return day.macroGapKilocalories
        }

        return macroGap(
            totalEnergyKcal: totalEnergy,
            proteinGrams: protein,
            carbohydrateGrams: carbs,
            fatGrams: fat
        )
    }
}
