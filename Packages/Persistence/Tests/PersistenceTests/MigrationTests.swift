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
                "meal",
                "exercise",
                "exercise_alias",
                "workout_session",
                "workout_block",
                "workout_session_exercise",
                "set_entry",
                "active_workout_state",
                "rest_timer_state",
                "rest_timer_event",
                "workout_template",
                "workout_template_exercise",
                "personal_record",
                "exercise_history_snapshot",
                "coach_recommendation",
                "readiness_daily_score",
                "readiness_baseline_state",
                "memory_profile",
                "plan_mesocycle_state",
                "planned_workout",
                "app_metadata",
                "chat_message",
                "training_plan_settings",
                "daily_brief",
                "meal_line_item",
                "food_product_cache",
                "food_portion_preference",
                "meal_template",
                "meal_template_item",
                "pending_food_import",
                "food_log_recent",
                "nutrition_day_log_status"
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
        let hasLoggerTables = try pool.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) > 0
                    FROM sqlite_master
                    WHERE type = 'table' AND name = 'workout_session'
                    """
            ) ?? false
        }
        return hasLoggerTables ? SchemaVersion.latest : 1
    }

    private static func applySchemaSnapshot(version: Int, to pool: DatabasePool) throws {
        let migrator = AppMigrator.makeMigrator(upTo: version)
        try migrator.migrate(pool)
    }
}
