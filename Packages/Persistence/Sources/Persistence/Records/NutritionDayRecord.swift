import Core
import Foundation
import GRDB

struct NutritionDayRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "nutrition_day"

    enum CodingKeys: String, CodingKey {
        case helmDay = "helm_day"
        case totalEnergyKcal = "total_energy_kcal"
        case totalProteinGrams = "total_protein_grams"
        case totalCarbohydrateGrams = "total_carbohydrate_grams"
        case totalFatGrams = "total_fat_grams"
        case macroGapKcal = "macro_gap_kcal"
        case updatedAt = "updated_at"
    }

    var helmDay: String
    var totalEnergyKcal: Double?
    var totalProteinGrams: Double?
    var totalCarbohydrateGrams: Double?
    var totalFatGrams: Double?
    var macroGapKcal: Double?
    var updatedAt: String

    init(day: NutritionDay, timestamp: Date = Date()) {
        helmDay = HelmDayColumn.encode(day.helmDay)
        totalEnergyKcal = day.totalEnergy?.kilocalories
        totalProteinGrams = day.totalProteinGrams
        totalCarbohydrateGrams = day.totalCarbohydrateGrams
        totalFatGrams = day.totalFatGrams
        macroGapKcal = day.macroGapKilocalories
        updatedAt = ISO8601Coding.string(from: timestamp)
    }

    func toValue() throws -> NutritionDay {
        NutritionDay(
            helmDay: try HelmDayColumn.decode(helmDay),
            totalEnergy: totalEnergyKcal.map { Energy(kilocalories: $0) },
            totalProteinGrams: totalProteinGrams,
            totalCarbohydrateGrams: totalCarbohydrateGrams,
            totalFatGrams: totalFatGrams,
            macroGapKilocalories: macroGapKcal
        )
    }
}
