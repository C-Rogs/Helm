import Core
import Foundation
import GRDB

public struct NutritionLogStatusRepository: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func fetchStatus(helmDay: HelmDay) throws -> NutritionDayLogStatus? {
        try pool.read { db in
            guard let record = try NutritionDayLogStatusRecord.fetchOne(db, key: HelmDayColumn.encode(helmDay)) else {
                return nil
            }
            return try record.toValue()
        }
    }

    public func isLoggingComplete(helmDay: HelmDay) throws -> Bool {
        try fetchStatus(helmDay: helmDay)?.loggingComplete ?? false
    }

    public func markComplete(helmDay: HelmDay, at date: Date = Date()) throws {
        try upsert(
            NutritionDayLogStatus(helmDay: helmDay, loggingComplete: true, markedAt: date)
        )
    }

    public func clearComplete(helmDay: HelmDay) throws {
        try pool.write { db in
            try NutritionDayLogStatusRecord
                .filter(Column("helm_day") == HelmDayColumn.encode(helmDay))
                .deleteAll(db)
        }
    }

    public func completeDays(from startDay: HelmDay, through endDay: HelmDay) throws -> Set<HelmDay> {
        try pool.read { db in
            let records = try NutritionDayLogStatusRecord
                .filter(Column("logging_complete") == true)
                .filter(Column("helm_day") >= HelmDayColumn.encode(startDay))
                .filter(Column("helm_day") <= HelmDayColumn.encode(endDay))
                .fetchAll(db)
            return Set(try records.map { try $0.toValue().helmDay })
        }
    }

    private func upsert(_ status: NutritionDayLogStatus) throws {
        try pool.write { db in
            try NutritionDayLogStatusRecord(status: status).save(db)
        }
    }
}
