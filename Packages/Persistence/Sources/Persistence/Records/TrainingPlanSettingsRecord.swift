import Foundation
import GRDB

struct TrainingPlanSettingsRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "training_plan_settings"

    enum CodingKeys: String, CodingKey {
        case id
        case settingsJSON = "settings_json"
        case updatedAt = "updated_at"
    }

    static let singletonID = 1

    var id: Int
    var settingsJSON: String
    var updatedAt: String

    init(settingsJSON: String, updatedAt: Date = Date()) {
        id = Self.singletonID
        self.settingsJSON = settingsJSON
        self.updatedAt = ISO8601Coding.string(from: updatedAt)
    }
}
