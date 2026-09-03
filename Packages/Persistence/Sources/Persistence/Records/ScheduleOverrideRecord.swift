import Foundation
import GRDB

struct ScheduleOverrideRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "schedule_override"

    enum CodingKeys: String, CodingKey {
        case id
        case overridesJSON = "overrides_json"
        case updatedAt = "updated_at"
    }

    static let singletonID = 1

    var id: Int
    var overridesJSON: String
    var updatedAt: String

    init(overridesJSON: String, updatedAt: Date = Date()) {
        id = Self.singletonID
        self.overridesJSON = overridesJSON
        self.updatedAt = ISO8601Coding.string(from: updatedAt)
    }
}
