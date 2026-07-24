import Core
import Foundation
import GRDB

struct FoodPortionPreferenceRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "food_portion_preference"

    enum CodingKeys: String, CodingKey {
        case foodRefKey = "food_ref_key"
        case foodOrigin = "food_origin"
        case foodExternalID = "food_external_id"
        case foodDisplayName = "food_display_name"
        case grams
        case servingLabel = "serving_label"
        case lastUsedAt = "last_used_at"
    }

    var foodRefKey: String
    var foodOrigin: String
    var foodExternalID: String
    var foodDisplayName: String
    var grams: Double
    var servingLabel: String?
    var lastUsedAt: String

    init(preference: FoodPortionPreference) {
        foodRefKey = FoodRefColumn.encode(preference.foodRef)
        foodOrigin = preference.foodRef.origin.rawValue
        foodExternalID = preference.foodRef.externalID
        foodDisplayName = preference.foodRef.displayName
        grams = preference.grams
        servingLabel = preference.servingLabel
        lastUsedAt = ISO8601Coding.string(from: preference.lastUsedAt)
    }

    func toValue() throws -> FoodPortionPreference {
        let foodRef = try FoodRefColumn.decode(
            key: foodRefKey,
            origin: foodOrigin,
            externalID: foodExternalID,
            displayName: foodDisplayName
        )
        return FoodPortionPreference(
            foodRef: foodRef,
            grams: grams,
            servingLabel: servingLabel,
            lastUsedAt: try ISO8601Coding.date(from: lastUsedAt)
        )
    }
}
