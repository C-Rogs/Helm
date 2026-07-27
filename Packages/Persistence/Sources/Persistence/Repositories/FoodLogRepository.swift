import Core
import Foundation
import GRDB

public struct FoodLogRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    // MARK: - Line items

    public func upsertLineItems(_ items: [MealLineItemRecord]) throws {
        try pool.write { db in
            for item in items {
                try MealLineItemRow(item: item).save(db)
            }
        }
    }

    public func replaceLineItems(for mealID: UUID, with items: [MealLineItemRecord]) throws {
        let mealKey = mealID.uuidString.lowercased()
        try pool.write { db in
            try MealLineItemRow
                .filter(Column("meal_id") == mealKey)
                .deleteAll(db)
            for item in items {
                try MealLineItemRow(item: item).save(db)
            }
        }
    }

    public func fetchLineItems(for mealID: UUID) throws -> [MealLineItemRecord] {
        try pool.read { db in
            let rows = try MealLineItemRow
                .filter(Column("meal_id") == mealID.uuidString.lowercased())
                .order(Column("sort_order"))
                .fetchAll(db)
            return try rows.map { try $0.toValue() }
        }
    }

    public func deleteLineItems(for mealID: UUID) throws {
        _ = try pool.write { db in
            try MealLineItemRow
                .filter(Column("meal_id") == mealID.uuidString.lowercased())
                .deleteAll(db)
        }
    }

    // MARK: - Product cache

    public func upsertCacheEntry(_ entry: FoodProductCacheEntry) throws {
        try pool.write { db in
            try FoodProductCacheRow(entry: entry).save(db)
        }
    }

    public func fetchCacheEntry(ref: FoodProductRef) throws -> FoodProductCacheEntry? {
        try pool.read { db in
            guard let row = try FoodProductCacheRow.fetchOne(db, key: FoodRefColumn.encode(ref)) else {
                return nil
            }
            return try row.toValue()
        }
    }

    public func fetchCacheEntries(limit: Int = 200) throws -> [FoodProductCacheEntry] {
        try pool.read { db in
            let rows = try FoodProductCacheRow
                .order(Column("updated_at").desc)
                .limit(limit)
                .fetchAll(db)
            return try rows.map { try $0.toValue() }
        }
    }

    public func deleteCacheEntry(ref: FoodProductRef) throws {
        _ = try pool.write { db in
            try FoodProductCacheRow.deleteOne(db, key: FoodRefColumn.encode(ref))
        }
    }

    // MARK: - Portion preferences

    public func upsertPortionPreference(_ preference: FoodPortionPreference) throws {
        try pool.write { db in
            try FoodPortionPreferenceRow(preference: preference).save(db)
        }
    }

    public func fetchPortionPreference(ref: FoodProductRef) throws -> FoodPortionPreference? {
        try pool.read { db in
            guard let row = try FoodPortionPreferenceRow.fetchOne(db, key: FoodRefColumn.encode(ref)) else {
                return nil
            }
            return try row.toValue()
        }
    }

    // MARK: - Recents

    public func upsertRecent(_ recent: FoodLogRecent) throws {
        try pool.write { db in
            try FoodLogRecentRow(recent: recent).save(db)
        }
    }

    public func fetchRecents(limit: Int = 50) throws -> [FoodLogRecent] {
        try pool.read { db in
            let rows = try FoodLogRecentRow
                .order(Column("last_used_at").desc)
                .limit(limit)
                .fetchAll(db)
            return try rows.map { try $0.toValue() }
        }
    }

    // MARK: - Pending imports

    public func insertPendingImport(_ importItem: PendingFoodImport) throws {
        try pool.write { db in
            try PendingFoodImportRow(importItem: importItem).insert(db)
        }
    }

    public func updatePendingImport(_ importItem: PendingFoodImport) throws {
        try pool.write { db in
            try PendingFoodImportRow(importItem: importItem).update(db)
        }
    }

    public func fetchPendingImports(status: PendingFoodImport.Status? = nil) throws -> [PendingFoodImport] {
        try pool.read { db in
            var request = PendingFoodImportRow.all()
            if let status {
                request = request.filter(Column("status") == status.rawValue)
            }
            let rows = try request
                .order(Column("created_at").desc)
                .fetchAll(db)
            return try rows.map { try $0.toValue() }
        }
    }

    public func deletePendingImport(id: UUID) throws {
        _ = try pool.write { db in
            try PendingFoodImportRow.deleteOne(db, key: id.uuidString.lowercased())
        }
    }
}
