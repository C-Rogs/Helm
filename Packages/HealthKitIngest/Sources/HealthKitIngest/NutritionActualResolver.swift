import Core
import Foundation
import NutritionKit

/// Builds the logged-day view model from meal rows and/or HealthKit daily dietary aggregates (e.g. MFP).
enum NutritionActualResolver {
    static func resolve(
        helmDay: HelmDay,
        storedDay: NutritionDay?,
        dailyMetrics: DailyMetrics?
    ) -> NutritionDay? {
        let fromMetrics = nutritionDay(from: dailyMetrics, helmDay: helmDay)
        guard let storedDay else {
            return fromMetrics
        }
        guard let fromMetrics else {
            return storedDay
        }

        let merged = NutritionDay(
            helmDay: helmDay,
            totalEnergy: prefer(storedDay.totalEnergy, fromMetrics.totalEnergy),
            totalProteinGrams: prefer(storedDay.totalProteinGrams, fromMetrics.totalProteinGrams),
            totalCarbohydrateGrams: prefer(storedDay.totalCarbohydrateGrams, fromMetrics.totalCarbohydrateGrams),
            totalFatGrams: prefer(storedDay.totalFatGrams, fromMetrics.totalFatGrams),
            macroGapKilocalories: storedDay.macroGapKilocalories ?? fromMetrics.macroGapKilocalories
        )

        return NutritionDay(
            helmDay: helmDay,
            totalEnergy: merged.totalEnergy,
            totalProteinGrams: merged.totalProteinGrams,
            totalCarbohydrateGrams: merged.totalCarbohydrateGrams,
            totalFatGrams: merged.totalFatGrams,
            macroGapKilocalories: MacroGapCalculator.macroGap(for: merged) ?? merged.macroGapKilocalories
        )
    }

    private static func nutritionDay(from metrics: DailyMetrics?, helmDay: HelmDay) -> NutritionDay? {
        guard let metrics, hasDietaryData(metrics) else { return nil }
        let day = NutritionDay(
            helmDay: helmDay,
            totalEnergy: metrics.dietaryEnergy,
            totalProteinGrams: metrics.dietaryProteinGrams,
            totalCarbohydrateGrams: metrics.dietaryCarbohydrateGrams,
            totalFatGrams: metrics.dietaryFatGrams
        )
        return NutritionDay(
            helmDay: helmDay,
            totalEnergy: day.totalEnergy,
            totalProteinGrams: day.totalProteinGrams,
            totalCarbohydrateGrams: day.totalCarbohydrateGrams,
            totalFatGrams: day.totalFatGrams,
            macroGapKilocalories: MacroGapCalculator.macroGap(for: day)
        )
    }

    private static func hasDietaryData(_ metrics: DailyMetrics) -> Bool {
        metrics.dietaryEnergy != nil
            || metrics.dietaryProteinGrams != nil
            || metrics.dietaryCarbohydrateGrams != nil
            || metrics.dietaryFatGrams != nil
    }

    private static func prefer(_ stored: Energy?, _ metrics: Energy?) -> Energy? {
        if let stored, let metrics {
            return stored.kilocalories >= metrics.kilocalories ? stored : metrics
        }
        return stored ?? metrics
    }

    private static func prefer(_ stored: Double?, _ metrics: Double?) -> Double? {
        if let stored, let metrics {
            return max(stored, metrics)
        }
        return stored ?? metrics
    }
}
