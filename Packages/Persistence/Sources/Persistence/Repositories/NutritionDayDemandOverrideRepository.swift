import Core
import Foundation
import GRDB

public struct NutritionDayDemandOverrideRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) { self.pool = pool }

    public func fetch(for day: HelmDay) throws -> NutritionDayDemandOverride? {
        try pool.read { db in
            try NutritionDayDemandOverrideRecord.fetchOne(db, key: HelmDayColumn.encode(day))?.model
        }
    }

    public func fetch(from start: HelmDay, through end: HelmDay) throws -> [NutritionDayDemandOverride] {
        try pool.read { db in
            try NutritionDayDemandOverrideRecord
                .filter(Column("helm_day") >= HelmDayColumn.encode(start))
                .filter(Column("helm_day") <= HelmDayColumn.encode(end))
                .order(Column("helm_day"))
                .fetchAll(db)
                .map { try $0.model }
        }
    }

    public func save(_ override: NutritionDayDemandOverride) throws {
        try pool.write { db in try NutritionDayDemandOverrideRecord(override).save(db) }
    }

    public func delete(for day: HelmDay) throws {
        _ = try pool.write { db in
            try NutritionDayDemandOverrideRecord.deleteOne(db, key: HelmDayColumn.encode(day))
        }
    }
}

private struct NutritionDayDemandOverrideRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "nutrition_day_demand_override"

    enum CodingKeys: String, CodingKey {
        case helmDay = "helm_day"
        case demand
        case updatedAt = "updated_at"
    }

    let helmDay: String
    let demand: String
    let updatedAt: String

    init(_ model: NutritionDayDemandOverride) {
        helmDay = HelmDayColumn.encode(model.helmDay)
        demand = model.demand.rawValue
        updatedAt = ISO8601Coding.string(from: model.updatedAt)
    }

    var model: NutritionDayDemandOverride {
        get throws {
            guard let demand = NutritionDayDemand(rawValue: demand) else {
                throw PersistenceError.migrationFailed("invalid nutrition day demand: \(self.demand)")
            }
            return NutritionDayDemandOverride(
                helmDay: try HelmDayColumn.decode(helmDay),
                demand: demand,
                updatedAt: try ISO8601Coding.date(from: updatedAt)
            )
        }
    }
}
