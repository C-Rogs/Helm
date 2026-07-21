import Core
import Foundation
import GRDB

public struct BodyCompositionRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func upsert(_ composition: BodyComposition) throws {
        try pool.write { db in
            try BodyCompositionRecord(composition: composition).save(db)
        }
    }

    public func fetch(id: UUID) throws -> BodyComposition? {
        try pool.read { db in
            guard let record = try BodyCompositionRecord.fetchOne(db, key: id.uuidString.lowercased()) else {
                return nil
            }
            return try record.toValue()
        }
    }

    public func fetch(for helmDay: HelmDay) throws -> [BodyComposition] {
        try pool.read { db in
            let records = try BodyCompositionRecord
                .filter(Column("helm_day") == HelmDayColumn.encode(helmDay))
                .order(Column("measured_at"))
                .fetchAll(db)
            return try records.map { try $0.toValue() }
        }
    }

    public func fetchLatest(onOrBefore helmDay: HelmDay, limit: Int = 1) throws -> [BodyComposition] {
        try pool.read { db in
            let records = try BodyCompositionRecord
                .filter(Column("helm_day") <= HelmDayColumn.encode(helmDay))
                .order(Column("measured_at").desc)
                .limit(limit)
                .fetchAll(db)
            return try records.map { try $0.toValue() }
        }
    }

    public func delete(id: UUID) throws {
        _ = try pool.write { db in
            try BodyCompositionRecord.deleteOne(db, key: id.uuidString.lowercased())
        }
    }
}
