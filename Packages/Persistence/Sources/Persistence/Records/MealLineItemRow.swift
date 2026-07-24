import Core
import Foundation
import GRDB

struct MealLineItemRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meal_line_item"

    enum CodingKeys: String, CodingKey {
        case id
        case mealID = "meal_id"
        case foodOrigin = "food_origin"
        case foodExternalID = "food_external_id"
        case foodDisplayName = "food_display_name"
        case grams
        case servingLabel = "serving_label"
        case energyKcal = "energy_kcal"
        case proteinGrams = "protein_grams"
        case carbohydrateGrams = "carbohydrate_grams"
        case fatGrams = "fat_grams"
        case sortOrder = "sort_order"
    }

    var id: String
    var mealID: String
    var foodOrigin: String
    var foodExternalID: String
    var foodDisplayName: String
    var grams: Double
    var servingLabel: String?
    var energyKcal: Double
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
    var sortOrder: Int

    init(item: MealLineItemRecord) {
        id = item.id.uuidString.lowercased()
        mealID = item.mealID.uuidString.lowercased()
        foodOrigin = item.foodRef.origin.rawValue
        foodExternalID = item.foodRef.externalID
        foodDisplayName = item.foodRef.displayName
        grams = item.grams
        servingLabel = item.servingLabel
        energyKcal = item.energyKcal
        proteinGrams = item.proteinG
        carbohydrateGrams = item.carbsG
        fatGrams = item.fatG
        sortOrder = item.sortOrder
    }

    func toValue() throws -> MealLineItemRecord {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.migrationFailed("invalid meal line item id: \(id)")
        }
        guard let mealUUID = UUID(uuidString: mealID) else {
            throw PersistenceError.migrationFailed("invalid meal id on line item: \(mealID)")
        }
        let foodRef = try FoodRefColumn.decode(
            key: "\(foodOrigin):\(foodExternalID)",
            origin: foodOrigin,
            externalID: foodExternalID,
            displayName: foodDisplayName
        )
        return MealLineItemRecord(
            id: uuid,
            mealID: mealUUID,
            foodRef: foodRef,
            grams: grams,
            servingLabel: servingLabel,
            energyKcal: energyKcal,
            proteinG: proteinGrams,
            carbsG: carbohydrateGrams,
            fatG: fatGrams,
            sortOrder: sortOrder
        )
    }
}
