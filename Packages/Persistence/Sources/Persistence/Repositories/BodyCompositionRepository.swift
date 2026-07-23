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

    public func listDays() throws -> [HelmDay] {
        try pool.read { db in
            let rows = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT helm_day FROM body_composition ORDER BY helm_day"
            )
            return try rows.map { try HelmDayColumn.decode($0) }
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

    /// Latest body-mass sample per day, newest days first.
    public func fetchDailyWeights(endingAt end: HelmDay, limit: Int, offset: Int = 0) throws -> [(HelmDay, Double)] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT bc.helm_day, bc.mass_kg
                    FROM body_composition bc
                    INNER JOIN (
                        SELECT helm_day, MAX(measured_at) AS max_measured
                        FROM body_composition
                        WHERE helm_day <= ?
                        GROUP BY helm_day
                    ) latest
                        ON bc.helm_day = latest.helm_day
                       AND bc.measured_at = latest.max_measured
                    ORDER BY bc.helm_day DESC
                    LIMIT ? OFFSET ?
                    """,
                arguments: [HelmDayColumn.encode(end), limit, offset]
            )
            return try rows.map { row in
                let dayString: String = row["helm_day"]
                let day = try HelmDayColumn.decode(dayString)
                let massKg: Double = row["mass_kg"]
                return (day, massKg)
            }
        }
    }
}
