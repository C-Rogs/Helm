import Foundation
import GRDB

struct ReadinessBaselineRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "readiness_baseline_state"

    enum CodingKeys: String, CodingKey {
        case id
        case stateJSON = "state_json"
        case updatedAt = "updated_at"
    }

    static let singletonID = 1

    var id: Int
    var stateJSON: String
    var updatedAt: String

    init(stateJSON: String, updatedAt: Date = Date()) {
        id = Self.singletonID
        self.stateJSON = stateJSON
        self.updatedAt = ISO8601Coding.string(from: updatedAt)
    }
}
