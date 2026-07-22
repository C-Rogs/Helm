import Core
import Foundation
import GRDB

public struct SleepRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func upsert(_ record: SleepRecord) throws {
        try pool.write { db in
            try SleepIntervalRecord(record: record).save(db)
        }
    }

    public func fetch(id: UUID) throws -> SleepRecord? {
        try pool.read { db in
            guard let row = try SleepIntervalRecord.fetchOne(db, key: id.uuidString.lowercased()) else {
                return nil
            }
            return try row.toValue()
        }
    }

    public func fetch(for helmDay: HelmDay) throws -> [SleepRecord] {
        try pool.read { db in
            let rows = try SleepIntervalRecord
                .filter(Column("helm_day") == HelmDayColumn.encode(helmDay))
                .order(Column("start_at"))
                .fetchAll(db)
            return try rows.map { try $0.toValue() }
        }
    }

    public func listDays() throws -> [HelmDay] {
        try pool.read { db in
            let rows = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT helm_day FROM sleep_record ORDER BY helm_day"
            )
            return try rows.map { try HelmDayColumn.decode($0) }
        }
    }

    public func replaceAll(for helmDay: HelmDay, records: [SleepRecord]) throws {
        try pool.write { db in
            try SleepIntervalRecord
                .filter(Column("helm_day") == HelmDayColumn.encode(helmDay))
                .deleteAll(db)
            for record in records {
                try SleepIntervalRecord(record: record).insert(db)
            }
        }
    }

    public func delete(id: UUID) throws {
        _ = try pool.write { db in
            try SleepIntervalRecord.deleteOne(db, key: id.uuidString.lowercased())
        }
    }
}
