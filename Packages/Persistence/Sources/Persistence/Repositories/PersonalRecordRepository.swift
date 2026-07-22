import Core
import Foundation
import GRDB

public struct PersonalRecordRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func insert(_ record: PersonalRecord, timestamp: Date = Date()) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO personal_record (
                        id, exercise_id, metric_type, metric_value,
                        source_set_entry_id, source_workout_session_id,
                        achieved_at, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    record.id,
                    record.exerciseID,
                    record.metricType.rawValue,
                    record.metricValue,
                    record.sourceSetEntryID,
                    record.sourceWorkoutSessionID,
                    ISO8601Coding.string(from: record.achievedAt),
                    now
                ]
            )
        }
    }

    public func fetchBest(
        exerciseID: String,
        metric: PRMetricType
    ) throws -> PersonalRecord? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, exercise_id, metric_type, metric_value,
                           source_set_entry_id, source_workout_session_id, achieved_at
                    FROM personal_record
                    WHERE exercise_id = ? AND metric_type = ?
                    ORDER BY metric_value DESC, achieved_at DESC
                    LIMIT 1
                    """,
                arguments: [exerciseID, metric.rawValue]
            ) else {
                return nil
            }
            return try Self.record(from: row)
        }
    }

    private static func record(from row: Row) throws -> PersonalRecord {
        guard let metricRaw: String = row["metric_type"],
              let metric = PRMetricType(rawValue: metricRaw) else {
            throw PersistenceError.migrationFailed("invalid personal_record metric_type")
        }
        let achievedAtString: String = row["achieved_at"]
        return PersonalRecord(
            id: row["id"],
            exerciseID: row["exercise_id"],
            metricType: metric,
            metricValue: row["metric_value"],
            sourceSetEntryID: row["source_set_entry_id"],
            sourceWorkoutSessionID: row["source_workout_session_id"],
            achievedAt: try ISO8601Coding.date(from: achievedAtString)
        )
    }
}
