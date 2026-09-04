import Foundation

/// Aggregated nutrition for one logical day, including meal-derived totals and macro gap.
public struct NutritionDay: Sendable, Hashable, Codable, Identifiable {
    public let helmDay: HelmDay
    public let totalEnergy: Energy?
    public let totalProteinGrams: Double?
    public let totalCarbohydrateGrams: Double?
    public let totalFatGrams: Double?
    /// Untracked energy (e.g. alcohol) above reconstructed macros; see NutritionKit.
    public let macroGapKilocalories: Double?
    /// Daily eat-to target persisted when NutritionEngine last resolved this day. Nil historically.
    public let eatToKilocalories: Double?

    public var id: HelmDay { helmDay }

    public init(
        helmDay: HelmDay,
        totalEnergy: Energy? = nil,
        totalProteinGrams: Double? = nil,
        totalCarbohydrateGrams: Double? = nil,
        totalFatGrams: Double? = nil,
        macroGapKilocalories: Double? = nil,
        eatToKilocalories: Double? = nil
    ) {
        self.helmDay = helmDay
        self.totalEnergy = totalEnergy
        self.totalProteinGrams = totalProteinGrams
        self.totalCarbohydrateGrams = totalCarbohydrateGrams
        self.totalFatGrams = totalFatGrams
        self.macroGapKilocalories = macroGapKilocalories
        self.eatToKilocalories = eatToKilocalories
    }
}
