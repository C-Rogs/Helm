import Foundation
import GRDB

public struct AppMetadataStore: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func value(forKey key: String) throws -> String? {
        try pool.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM app_metadata WHERE key = ?",
                arguments: [key]
            )
        }
    }

    public func setValue(_ value: String?, forKey key: String) throws {
        let now = ISO8601Coding.string(from: Date())
        try pool.write { db in
            if let value {
                try db.execute(
                    sql: """
                        INSERT INTO app_metadata (key, value, updated_at)
                        VALUES (?, ?, ?)
                        ON CONFLICT(key) DO UPDATE SET
                            value = excluded.value,
                            updated_at = excluded.updated_at
                        """,
                    arguments: [key, value, now]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM app_metadata WHERE key = ?",
                    arguments: [key]
                )
            }
        }
    }
}
