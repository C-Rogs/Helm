import Foundation
import GRDB

struct MemoryProfileRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "memory_profile"

    enum CodingKeys: String, CodingKey {
        case id
        case profileJSON = "profile_json"
        case updatedAt = "updated_at"
    }

    static let singletonID = 1

    var id: Int
    var profileJSON: String
    var updatedAt: String

    init(profileJSON: String, updatedAt: Date = Date()) {
        id = Self.singletonID
        self.profileJSON = profileJSON
        self.updatedAt = ISO8601Coding.string(from: updatedAt)
    }
}
