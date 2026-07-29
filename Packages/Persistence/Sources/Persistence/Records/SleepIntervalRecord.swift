import Core
import Foundation
import GRDB

struct SleepIntervalRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sleep_record"

    enum CodingKeys: String, CodingKey {
        case id
        case helmDay = "helm_day"
        case startAt = "start_at"
        case endAt = "end_at"
        case stage
        case sourceBundleID = "source_bundle_id"
    }

    var id: String
    var helmDay: String
    var startAt: String
    var endAt: String
    var stage: String
    var sourceBundleID: String?

    init(record: SleepRecord) {
        id = record.id.uuidString.lowercased()
        helmDay = HelmDayColumn.encode(record.helmDay)
        startAt = ISO8601Coding.string(from: record.start)
        endAt = ISO8601Coding.string(from: record.end)
        stage = record.stage.rawValue
        sourceBundleID = record.sourceBundleID
    }

    func toValue() throws -> SleepRecord {
        guard let uuid = UUID(uuidString: id) else {
            throw PersistenceError.migrationFailed("invalid sleep record id: \(id)")
        }
        let decodedStage = SleepAnalysisStage(rawValue: stage) ?? .asleepUnspecified
        return SleepRecord(
            id: uuid,
            start: try ISO8601Coding.date(from: startAt),
            end: try ISO8601Coding.date(from: endAt),
            helmDay: try HelmDayColumn.decode(helmDay),
            stage: decodedStage,
            sourceBundleID: sourceBundleID
        )
    }
}
