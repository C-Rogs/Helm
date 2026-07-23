import Core
import Foundation

public struct MacroTargets: Sendable, Hashable, Codable, Equatable {
    public let caloriesKcal: Int
    public let proteinGrams: Int
    public let carbohydrateGrams: Int
    public let fatGrams: Int
    public let dayType: NutritionDayType
    public let estimatedTDEEKcal: Int
    /// Logged untracked energy (e.g. alcohol) for the day; never folded into carb/fat targets.
    public let macroGapKilocalories: Double?

    public init(
        caloriesKcal: Int,
        proteinGrams: Int,
        carbohydrateGrams: Int,
        fatGrams: Int,
        dayType: NutritionDayType,
        estimatedTDEEKcal: Int,
        macroGapKilocalories: Double? = nil
    ) {
        self.caloriesKcal = caloriesKcal
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.dayType = dayType
        self.estimatedTDEEKcal = estimatedTDEEKcal
        self.macroGapKilocalories = macroGapKilocalories
    }

    public var summary: NutritionTargetsSummary {
        NutritionTargetsSummary(
            caloriesKcal: caloriesKcal,
            proteinGrams: proteinGrams,
            carbohydrateGrams: carbohydrateGrams,
            fatGrams: fatGrams,
            dayType: dayType.rawValue
        )
    }
}
