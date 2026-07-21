import Core
import Foundation
import GRDB

public struct NutritionRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func upsertDay(_ day: NutritionDay) throws {
        try pool.write { db in
            try NutritionDayRecord(day: day).save(db)
        }
    }

    public func fetchDay(helmDay: HelmDay) throws -> NutritionDay? {
        try pool.read { db in
            guard let record = try NutritionDayRecord.fetchOne(db, key: HelmDayColumn.encode(helmDay)) else {
                return nil
            }
            return try record.toValue()
        }
    }

    public func upsertMeal(_ meal: MealRecord) throws {
        try pool.write { db in
            try MealRow(meal: meal).save(db)
        }
    }

    public func fetchMeals(for helmDay: HelmDay) throws -> [MealRecord] {
        try pool.read { db in
            let rows = try MealRow
                .filter(Column("helm_day") == HelmDayColumn.encode(helmDay))
                .order(Column("logged_at"))
                .fetchAll(db)
            return try rows.map { try $0.toValue() }
        }
    }

    public func fetchMeal(id: UUID) throws -> MealRecord? {
        try pool.read { db in
            guard let row = try MealRow.fetchOne(db, key: id.uuidString.lowercased()) else {
                return nil
            }
            return try row.toValue()
        }
    }

    public func deleteMeal(id: UUID) throws {
        _ = try pool.write { db in
            try MealRow.deleteOne(db, key: id.uuidString.lowercased())
        }
    }

    public func deleteDay(helmDay: HelmDay) throws {
        try pool.write { db in
            try MealRow
                .filter(Column("helm_day") == HelmDayColumn.encode(helmDay))
                .deleteAll(db)
            try NutritionDayRecord.deleteOne(db, key: HelmDayColumn.encode(helmDay))
        }
    }
}
