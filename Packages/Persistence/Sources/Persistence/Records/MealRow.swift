import Core
import Foundation
import GRDB

struct MealRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meal"

    enum CodingKeys: String, CodingKey {
        case id
        case helmDay = "helm_day"
        case name
        case loggedAt = "logged_at"
        case energyKcal = "energy_kcal"
        case proteinGrams = "protein_grams"
        case carbohydrateGrams = "carbohydrate_grams"
        case fatGrams = "fat_grams"
        case source
        case externalSampleID = "external_sample_id"
    }

    var id: String
    var helmDay: String
    var name: String
    var loggedAt: String
    var energyKcal: Double?
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var fatGrams: Double?
    var source: String
    var externalSampleID: String?

    init(meal: MealRecord) {
        id = meal.id.uuidString.lowercased()
        helmDay = HelmDayColumn.encode(meal.helmDay)
        name = meal.name
        loggedAt = ISO8601Coding.string(from: meal.loggedAt)
        energyKcal = meal.energy?.kilocalories
        proteinGrams = meal.proteinGrams
        carbohydrateGrams = meal.carbohydrateGrams
        fatGrams = meal.fatGrams
        source = meal.source.rawValue
        externalSampleID = meal.externalSampleID
    }

    func toValue() throws -> MealRecord {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.migrationFailed("invalid meal id: \(id)")
        }
        guard let mealSource = MealRecord.Source(rawValue: source) else {
            throw PersistenceError.migrationFailed("invalid meal source: \(source)")
        }
        return MealRecord(
            id: uuid,
            helmDay: try HelmDayColumn.decode(helmDay),
            name: name,
            loggedAt: try ISO8601Coding.date(from: loggedAt),
            energy: energyKcal.map { Energy(kilocalories: $0) },
            proteinGrams: proteinGrams,
            carbohydrateGrams: carbohydrateGrams,
            fatGrams: fatGrams,
            source: mealSource,
            externalSampleID: externalSampleID
        )
    }
}
