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
            var record = NutritionDayRecord(day: day)
            if record.eatToKcal == nil,
               let existing = try NutritionDayRecord.fetchOne(db, key: record.helmDay) {
                record.eatToKcal = existing.eatToKcal
            }
            try record.save(db)
        }
    }

    public func updateEatToKcal(helmDay: HelmDay, kcal: Double) throws {
        try pool.write { db in
            let key = HelmDayColumn.encode(helmDay)
            if var existing = try NutritionDayRecord.fetchOne(db, key: key) {
                existing.eatToKcal = kcal
                existing.updatedAt = ISO8601Coding.string(from: Date())
                try existing.update(db)
            } else {
                try NutritionDayRecord(
                    day: NutritionDay(helmDay: helmDay, eatToKilocalories: kcal)
                ).insert(db)
            }
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

    public func listDays() throws -> [HelmDay] {
        try pool.read { db in
            let rows = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT helm_day FROM nutrition_day ORDER BY helm_day"
            )
            return try rows.map { try HelmDayColumn.decode($0) }
        }
    }

    public func fetchRange(from startDay: HelmDay, through endDay: HelmDay) throws -> [NutritionDay] {
        try pool.read { db in
            let records = try NutritionDayRecord
                .filter(Column("helm_day") >= HelmDayColumn.encode(startDay))
                .filter(Column("helm_day") <= HelmDayColumn.encode(endDay))
                .order(Column("helm_day"))
                .fetchAll(db)
            return try records.map { try $0.toValue() }
        }
    }

    /// Paginated nutrition days, newest first.
    public func fetchDays(endingAt end: HelmDay, limit: Int, offset: Int = 0) throws -> [NutritionDay] {
        try pool.read { db in
            let records = try NutritionDayRecord
                .filter(Column("helm_day") <= HelmDayColumn.encode(end))
                .order(Column("helm_day").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
            return try records.map { try $0.toValue() }
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

    /// Fetch all meals within a helm day range (inclusive).
    public func fetchMealsInRange(from startDay: HelmDay, through endDay: HelmDay) throws -> [MealRecord] {
        try pool.read { db in
            let rows = try MealRow
                .filter(Column("helm_day") >= HelmDayColumn.encode(startDay))
                .filter(Column("helm_day") <= HelmDayColumn.encode(endDay))
                .order(Column("logged_at").desc)
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
            try MealLineItemRow
                .filter(Column("meal_id") == id.uuidString.lowercased())
                .deleteAll(db)
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
