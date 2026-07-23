import Core
import Foundation
import GRDB

public struct BriefStore: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func fetch(for helmDay: HelmDay) throws -> StoredDailyBrief? {
        try pool.read { db in
            guard let record = try DailyBriefRecord.fetchOne(db, key: helmDay.formatted) else {
                return nil
            }
            return try record.toValue()
        }
    }

    public func save(_ brief: StoredDailyBrief) throws {
        try pool.write { db in
            try DailyBriefRecord(brief: brief).save(db)
        }
    }

    public func delete(for helmDay: HelmDay) throws {
        _ = try pool.write { db in
            try DailyBriefRecord.deleteOne(db, key: helmDay.formatted)
        }
    }
}
