import Core
import Foundation
import GRDB

struct DailyBriefRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "daily_brief"

    enum CodingKeys: String, CodingKey {
        case helmDay = "helm_day"
        case inputFingerprint = "input_fingerprint"
        case engineText = "engine_text"
        case narrationText = "narration_text"
        case citationIDsJSON = "citation_ids_json"
        case source
        case promptVersion = "prompt_version"
        case schemaVersion = "schema_version"
        case updatedAt = "updated_at"
    }

    var helmDay: String
    var inputFingerprint: String
    var engineText: String
    var narrationText: String
    var citationIDsJSON: String
    var source: String
    var promptVersion: String?
    var schemaVersion: String?
    var updatedAt: String

    init(brief: StoredDailyBrief) throws {
        helmDay = HelmDayColumn.encode(brief.helmDay)
        inputFingerprint = brief.inputFingerprint
        engineText = brief.engineText
        narrationText = brief.narrationText
        let citationData = try JSONEncoder().encode(brief.citationIDs)
        guard let citationJSON = String(data: citationData, encoding: .utf8) else {
            throw PersistenceError.migrationFailed("failed to encode brief citations")
        }
        citationIDsJSON = citationJSON
        source = brief.source.rawValue
        promptVersion = brief.promptVersion
        schemaVersion = brief.schemaVersion
        updatedAt = ISO8601Coding.string(from: brief.updatedAt)
    }

    func toValue() throws -> StoredDailyBrief {
        guard let source = BriefNarrationSource(rawValue: source) else {
            throw PersistenceError.migrationFailed("unknown brief source: \(source)")
        }
        guard let citationData = citationIDsJSON.data(using: .utf8) else {
            throw PersistenceError.migrationFailed("invalid brief citations json")
        }
        let citationIDs = try JSONDecoder().decode([String].self, from: citationData)
        return StoredDailyBrief(
            helmDay: try HelmDayColumn.decode(helmDay),
            inputFingerprint: inputFingerprint,
            engineText: engineText,
            narrationText: narrationText,
            citationIDs: citationIDs,
            source: source,
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            updatedAt: try ISO8601Coding.date(from: updatedAt)
        )
    }
}
