import Core
import Foundation
import GRDB

struct FoodProductCacheRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "food_product_cache"

    enum CodingKeys: String, CodingKey {
        case foodRefKey = "food_ref_key"
        case foodOrigin = "food_origin"
        case foodExternalID = "food_external_id"
        case displayName = "display_name"
        case per100gKcal = "per_100g_kcal"
        case per100gProtein = "per_100g_protein"
        case per100gCarbs = "per_100g_carbs"
        case per100gFat = "per_100g_fat"
        case snapshotJSON = "snapshot_json"
        case updatedAt = "updated_at"
    }

    var foodRefKey: String
    var foodOrigin: String
    var foodExternalID: String
    var displayName: String
    var per100gKcal: Double
    var per100gProtein: Double
    var per100gCarbs: Double
    var per100gFat: Double
    var snapshotJSON: String?
    var updatedAt: String

    init(entry: FoodProductCacheEntry) {
        foodRefKey = FoodRefColumn.encode(entry.ref)
        foodOrigin = entry.ref.origin.rawValue
        foodExternalID = entry.ref.externalID
        displayName = entry.ref.displayName
        per100gKcal = entry.per100gKcal
        per100gProtein = entry.per100gProteinG
        per100gCarbs = entry.per100gCarbsG
        per100gFat = entry.per100gFatG
        snapshotJSON = entry.snapshotJSON
        updatedAt = ISO8601Coding.string(from: entry.updatedAt)
    }

    func toValue() throws -> FoodProductCacheEntry {
        let ref = try FoodRefColumn.decode(
            key: foodRefKey,
            origin: foodOrigin,
            externalID: foodExternalID,
            displayName: displayName
        )
        return FoodProductCacheEntry(
            ref: ref,
            per100gKcal: per100gKcal,
            per100gProteinG: per100gProtein,
            per100gCarbsG: per100gCarbs,
            per100gFatG: per100gFat,
            snapshotJSON: snapshotJSON,
            updatedAt: try ISO8601Coding.date(from: updatedAt)
        )
    }
}
