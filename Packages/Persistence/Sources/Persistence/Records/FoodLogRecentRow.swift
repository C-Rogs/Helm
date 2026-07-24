import Core
import Foundation
import GRDB

struct FoodLogRecentRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "food_log_recent"

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

    init(recent: FoodLogRecent) {
        foodRefKey = FoodRefColumn.encode(recent.ref)
        foodOrigin = recent.ref.origin.rawValue
        foodExternalID = recent.ref.externalID
        foodDisplayName = recent.ref.displayName
        grams = recent.grams
        servingLabel = recent.servingLabel
        lastUsedAt = ISO8601Coding.string(from: recent.lastUsedAt)
    }

    func toValue() throws -> FoodLogRecent {
        let ref = try FoodRefColumn.decode(
            key: foodRefKey,
            origin: foodOrigin,
            externalID: foodExternalID,
            displayName: foodDisplayName
        )
        return FoodLogRecent(
            ref: ref,
            grams: grams,
            servingLabel: servingLabel,
            lastUsedAt: try ISO8601Coding.date(from: lastUsedAt)
        )
    }
}
