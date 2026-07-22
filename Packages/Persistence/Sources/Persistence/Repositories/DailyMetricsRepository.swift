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
