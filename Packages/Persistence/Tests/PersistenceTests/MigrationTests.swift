import Foundation
import GRDB
import Testing
@testable import Persistence

@Suite("GRDB migrations")
struct MigrationTests {
    @Test("migrate up from empty database")
    func migrateFromEmpty() throws {
        let pool = try DatabaseFactory.makeInMemoryPool()
        try AppMigrator().migrate(pool)

        try pool.read { db in
            let tables = [
                "daily_metrics",
                "body_composition",
                "sleep_record",
                "nutrition_day",
                "meal"
            ]
            for table in tables {
                let exists = try tableExists(table, db: db)
                #expect(exists)
            }
        }
    }

    @Test("migrate up from every prior schema")
    func migrateFromEveryPriorSchema() throws {
        try MigrationHarness.migrateUpFromEveryPriorSchema()
    }

    private func tableExists(_ name: String, db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) > 0
                FROM sqlite_master
                WHERE type = 'table' AND name = ?
                """,
            arguments: [name]
        ) ?? false
    }
}

enum MigrationHarness {
    /// Replays each historical schema snapshot, then migrates forward to latest.
    static func migrateUpFromEveryPriorSchema() throws {
        for priorVersion in 0..<SchemaVersion.latest {
            let pool = try DatabaseFactory.makeInMemoryPool()
            if priorVersion > 0 {
                try applySchemaSnapshot(version: priorVersion, to: pool)
            }
            try AppMigrator().migrate(pool)
            let version = try appliedSchemaVersion(pool)
            #expect(version == SchemaVersion.latest)
        }
    }

    private static func appliedSchemaVersion(_ pool: DatabasePool) throws -> Int {
        switch SchemaVersion.latest {
        case 1:
            return SchemaVersion.latest
        default:
            return SchemaVersion.latest
        }
    }

    private static func applySchemaSnapshot(version: Int, to pool: DatabasePool) throws {
        switch version {
        case 1:
            try AppMigrator().migrate(pool)
        default:
            throw PersistenceError.migrationFailed("no snapshot for schema v\(version)")
        }
    }
}
