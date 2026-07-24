import Core
import Foundation
import GRDB

public struct MealTemplateRepository: Sendable {
    private let pool: DatabasePool
    private let lineItemEncoder = JSONEncoder()
    private let lineItemDecoder = JSONDecoder()

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func save(_ template: MealTemplate) throws {
        let templateID = template.id.uuidString.lowercased()
        let updatedAt = ISO8601Coding.string(from: template.updatedAt)
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meal_template (id, name, bucket, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        bucket = excluded.bucket,
                        updated_at = excluded.updated_at
                    """,
                arguments: [templateID, template.name, template.bucket.rawValue, updatedAt]
            )

            try db.execute(
                sql: "DELETE FROM meal_template_item WHERE meal_template_id = ?",
                arguments: [templateID]
            )

            for (index, lineItem) in template.lineItems.enumerated() {
                let json = try lineItemEncoder.encode(lineItem)
                guard let jsonString = String(data: json, encoding: .utf8) else {
                    throw PersistenceError.migrationFailed("failed to encode meal template line item")
                }
                try db.execute(
                    sql: """
                        INSERT INTO meal_template_item (id, meal_template_id, line_item_json, sort_order)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [UUID().uuidString.lowercased(), templateID, jsonString, index]
                )
            }
        }
    }

    public func fetchAll() throws -> [MealTemplate] {
        try pool.read { db in
            let templateRows = try Row.fetchAll(
                db,
                sql: "SELECT id, name, bucket, updated_at FROM meal_template ORDER BY name COLLATE NOCASE ASC"
            )
            return try templateRows.map { row in
                try fetchTemplate(from: row, db: db)
            }
        }
    }

    public func fetch(id: UUID) throws -> MealTemplate? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT id, name, bucket, updated_at FROM meal_template WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            ) else {
                return nil
            }
            return try fetchTemplate(from: row, db: db)
        }
    }

    public func delete(id: UUID) throws {
        _ = try pool.write { db in
            try db.execute(
                sql: "DELETE FROM meal_template WHERE id = ?",
                arguments: [id.uuidString.lowercased()]
            )
        }
    }

    private func fetchTemplate(from row: Row, db: Database) throws -> MealTemplate {
        guard let templateID = UUID(uuidString: row["id"]) else {
            throw PersistenceError.migrationFailed("invalid meal template id: \(row["id"] ?? "")")
        }
        guard let bucket = MealBucket(rawValue: row["bucket"]) else {
            throw PersistenceError.migrationFailed("invalid meal template bucket: \(row["bucket"] ?? "")")
        }
        let itemRows = try Row.fetchAll(
            db,
            sql: """
                SELECT line_item_json
                FROM meal_template_item
                WHERE meal_template_id = ?
                ORDER BY sort_order ASC
                """,
            arguments: [templateID.uuidString.lowercased()]
        )
        let lineItems = try itemRows.map { itemRow -> MealLineItem in
            let jsonString: String = itemRow["line_item_json"]
            guard let data = jsonString.data(using: .utf8) else {
                throw PersistenceError.migrationFailed("invalid meal template line item json")
            }
            return try lineItemDecoder.decode(MealLineItem.self, from: data)
        }
        return MealTemplate(
            id: templateID,
            name: row["name"],
            bucket: bucket,
            lineItems: lineItems,
            updatedAt: try ISO8601Coding.date(from: row["updated_at"])
        )
    }
}
