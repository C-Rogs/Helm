import Core
import Foundation
import GRDB

public struct DailyMetricsRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func upsert(_ metrics: DailyMetrics) throws {
        try pool.write { db in
            try DailyMetricsRecord(metrics: metrics).save(db)
        }
    }

    /// Scales every stored prior-day TRIMP by `factor` (one-time epoch migration).
    /// Returns the number of rows updated.
    public func scaleAllPriorDayTRIMP(by factor: Double) throws -> Int {
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE daily_metrics
                    SET prior_day_trimp = prior_day_trimp * ?, updated_at = ?
                    WHERE prior_day_trimp IS NOT NULL
                    """,
                arguments: [factor, ISO8601Coding.string(from: Date())]
            )
            return db.changesCount
        }
    }

    public func fetch(helmDay: HelmDay) throws -> DailyMetrics? {
        try pool.read { db in
            guard let record = try DailyMetricsRecord.fetchOne(db, key: HelmDayColumn.encode(helmDay)) else {
                return nil
            }
            return try record.toValue()
        }
    }

    public func fetchRange(from start: HelmDay, through end: HelmDay) throws -> [DailyMetrics] {
        try pool.read { db in
            let records = try DailyMetricsRecord
                .filter(Column("helm_day") >= HelmDayColumn.encode(start))
                .filter(Column("helm_day") <= HelmDayColumn.encode(end))
                .order(Column("helm_day"))
                .fetchAll(db)
            return try records.map { try $0.toValue() }
        }
    }

    public func listDays(where column: DailyMetricColumn) throws -> [HelmDay] {
        try pool.read { db in
            let rows = try String.fetchAll(
                db,
                sql: """
                SELECT DISTINCT helm_day
                FROM daily_metrics
                WHERE \(column.rawValue) IS NOT NULL
                ORDER BY helm_day
                """
            )
            return try rows.map { try HelmDayColumn.decode($0) }
        }
    }

    public func listDays() throws -> [HelmDay] {
        try pool.read { db in
            let rows = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT helm_day FROM daily_metrics ORDER BY helm_day"
            )
            return try rows.map { try HelmDayColumn.decode($0) }
        }
    }

    public func delete(helmDay: HelmDay) throws {
        _ = try pool.write { db in
            try DailyMetricsRecord.deleteOne(db, key: HelmDayColumn.encode(helmDay))
        }
    }
}
