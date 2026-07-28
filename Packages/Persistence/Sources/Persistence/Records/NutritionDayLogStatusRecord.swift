import Core
import Foundation
import GRDB

struct NutritionDayLogStatusRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "nutrition_day_log_status"

    enum CodingKeys: String, CodingKey {
        case helmDay = "helm_day"
        case loggingComplete = "logging_complete"
        case markedAt = "marked_at"
    }

    var helmDay: String
    var loggingComplete: Bool
    var markedAt: String

    init(status: NutritionDayLogStatus) {
        helmDay = HelmDayColumn.encode(status.helmDay)
        loggingComplete = status.loggingComplete
        markedAt = ISO8601Coding.string(from: status.markedAt)
    }

    func toValue() throws -> NutritionDayLogStatus {
        NutritionDayLogStatus(
            helmDay: try HelmDayColumn.decode(helmDay),
            loggingComplete: loggingComplete,
            markedAt: try ISO8601Coding.date(from: markedAt)
        )
    }
}
