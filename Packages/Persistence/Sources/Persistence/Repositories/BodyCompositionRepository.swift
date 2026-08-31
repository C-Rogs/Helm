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

    public func fetchLatestWithBodyFat(onOrBefore helmDay: HelmDay) throws -> BodyComposition? {
        try fetchBodyFatHistory(onOrBefore: helmDay, limit: 1).first
    }

    public func fetchBodyFatHistory(onOrBefore helmDay: HelmDay, limit: Int) throws -> [BodyComposition] {
        try pool.read { db in
            let records = try BodyCompositionRecord
                .filter(Column("helm_day") <= HelmDayColumn.encode(helmDay))
                .filter(Column("body_fat_percentage") != nil)
                .order(Column("measured_at").desc)
                .limit(max(limit, 1))
                .fetchAll(db)
            return try records.map { try $0.toValue() }
        }
    }

    public func delete(id: UUID) throws {
        _ = try pool.write { db in
            try BodyCompositionRecord.deleteOne(db, key: id.uuidString.lowercased())
        }
    }

    public func mergeBodyFat(helmDay: HelmDay, bodyFatPercentage: Double, measuredAt: Date) throws {
        try pool.write { db in
            if var existing = try BodyCompositionRecord
                .filter(Column("helm_day") == HelmDayColumn.encode(helmDay))
                .order(Column("measured_at").desc)
                .fetchOne(db)
            {
                existing.bodyFatPercentage = bodyFatPercentage
                let shouldAdvanceTimestamp: Bool
                if let existingDate = try? ISO8601Coding.date(from: existing.measuredAt) {
                    shouldAdvanceTimestamp = measuredAt > existingDate
                } else {
                    shouldAdvanceTimestamp = true
                }
                if shouldAdvanceTimestamp {
                    existing.measuredAt = ISO8601Coding.string(from: measuredAt)
                }
                try existing.save(db)
            } else {
                let composition = BodyComposition(
                    helmDay: helmDay,
                    mass: Mass(kilograms: 0),
                    bodyFatPercentage: bodyFatPercentage,
                    measuredAt: measuredAt
                )
                try BodyCompositionRecord(composition: composition).save(db)
            }
        }
    }

    public func mergeBodyMass(helmDay: HelmDay, massKg: Double, measuredAt: Date, sampleID: UUID) throws {
        try pool.write { db in
            if var existing = try BodyCompositionRecord
                .filter(Column("helm_day") == HelmDayColumn.encode(helmDay))
                .order(Column("measured_at").desc)
                .fetchOne(db)
            {
                existing.massKg = massKg
                existing.id = sampleID.uuidString.lowercased()
                try existing.save(db)
            } else {
                let composition = BodyComposition(
                    id: sampleID,
                    helmDay: helmDay,
                    mass: Mass(kilograms: massKg),
                    measuredAt: measuredAt
                )
                try BodyCompositionRecord(composition: composition).save(db)
            }
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
