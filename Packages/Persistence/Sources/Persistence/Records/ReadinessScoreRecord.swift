import Core
import Foundation
import GRDB

struct ReadinessScoreRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "readiness_daily_score"

    enum CodingKeys: String, CodingKey {
        case helmDay = "helm_day"
        case scoreJSON = "score_json"
        case computedAt = "computed_at"
    }

    var helmDay: String
    var scoreJSON: String
    var computedAt: String

    init(helmDay: HelmDay, scoreJSON: String, computedAt: Date = Date()) {
        self.helmDay = HelmDayColumn.encode(helmDay)
        self.scoreJSON = scoreJSON
        self.computedAt = ISO8601Coding.string(from: computedAt)
    }

    func decodedHelmDay() throws -> HelmDay {
        try HelmDayColumn.decode(helmDay)
    }
}
