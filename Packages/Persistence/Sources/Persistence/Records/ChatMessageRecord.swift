import Foundation
import GRDB

struct ChatMessageRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "chat_message"

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case promptVersion = "prompt_version"
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case sortIndex = "sort_index"
    }

    var id: String
    var role: String
    var text: String
    var promptVersion: String
    var schemaVersion: String?
    var createdAt: String
    var sortIndex: Int
}
