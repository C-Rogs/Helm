import Foundation
import GRDB

/// v15: indexes, soft-delete-safe set uniqueness, logged_exercise_id backfill.
enum SchemaHardeningMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v15_schema_hardening") { db in
            try backfillLoggedExerciseIDs(db)
            try rebuildSetEntryForSoftDeleteUnique(db)
            try replaceWorkoutSessionStatusIndex(db)
            try createSupportingIndexes(db)
        }
    }

    private static func backfillLoggedExerciseIDs(_ db: Database) throws {
        try db.execute(
            sql: """
                UPDATE set_entry
                SET logged_exercise_id = (
                    SELECT wse.exercise_id
                    FROM workout_session_exercise wse
                    WHERE wse.id = set_entry.workout_session_exercise_id
                )
                WHERE logged_exercise_id IS NULL
                """
        )
        // Drop impossible orphans before NOT NULL rebuild (should be zero with FKs on).
        try db.execute(sql: "DELETE FROM set_entry WHERE logged_exercise_id IS NULL")
    }

    /// Drop unconditional UNIQUE(workout_session_exercise_id, set_index) so soft-deleted
    /// rows no longer block reusing set_index. Rebuild keeps FKs and other indexes.
    private static func rebuildSetEntryForSoftDeleteUnique(_ db: Database) throws {
        try db.execute(sql: "PRAGMA foreign_keys = OFF")

        try db.create(table: "set_entry_new") { table in
            table.column("id", .text).primaryKey()
            table.column("workout_session_exercise_id", .text).notNull()
                .references("workout_session_exercise", onDelete: .cascade)
            table.column("logged_exercise_id", .text).notNull().references("exercise")
            table.column("set_index", .integer).notNull()
            table.column("set_type", .text).notNull()
            table.column("status", .text).notNull().defaults(to: "planned")
            table.column("weight_kg", .double)
            table.column("reps", .integer)
            table.column("distance_km", .double)
            table.column("duration_seconds", .integer)
            table.column("rpe", .double)
            table.column("rir", .double)
            table.column("note", .text)
            table.column("bodyweight_kg_snapshot", .double)
            table.column("assistance_weight_kg", .double)
            table.column("completed_at", .text)
            table.column("created_at", .text).notNull()
            table.column("updated_at", .text).notNull()
            table.column("deleted_at", .text)
        }

        try db.execute(
            sql: """
                INSERT INTO set_entry_new (
                    id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                    weight_kg, reps, distance_km, duration_seconds, rpe, rir, note,
                    bodyweight_kg_snapshot, assistance_weight_kg, completed_at,
                    created_at, updated_at, deleted_at
                )
                SELECT
                    id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                    weight_kg, reps, distance_km, duration_seconds, rpe, rir, note,
                    bodyweight_kg_snapshot, assistance_weight_kg, completed_at,
                    created_at, updated_at, deleted_at
                FROM set_entry
                """
        )

        try db.drop(table: "set_entry")
        try db.rename(table: "set_entry_new", to: "set_entry")

        try db.create(
            index: "idx_set_entry_exercise_order",
            on: "set_entry",
            columns: ["workout_session_exercise_id", "set_index"]
        )
        try db.create(
            index: "idx_set_entry_completed",
            on: "set_entry",
            columns: ["status", "completed_at"]
        )
        try db.create(
            index: "idx_set_entry_active_set_index",
            on: "set_entry",
            columns: ["workout_session_exercise_id", "set_index"],
            unique: true,
            condition: SQL("deleted_at IS NULL")
        )
        try db.create(
            index: "idx_set_entry_logged_exercise",
            on: "set_entry",
            columns: ["logged_exercise_id", "status", "completed_at"]
        )

        try db.execute(sql: "PRAGMA foreign_keys = ON")
    }

    private static func replaceWorkoutSessionStatusIndex(_ db: Database) throws {
        try db.drop(index: "idx_workout_session_status")
        try db.create(
            index: "idx_workout_session_status_deleted_started",
            on: "workout_session",
            columns: ["status", "deleted_at", "started_at"]
        )
    }

    private static func createSupportingIndexes(_ db: Database) throws {
        try db.create(
            index: "idx_workout_block_session",
            on: "workout_block",
            columns: ["workout_session_id"]
        )
        try db.create(
            index: "idx_sleep_record_overlap",
            on: "sleep_record",
            columns: ["start_at", "end_at"]
        )
        try db.create(
            index: "idx_coach_recommendation_session",
            on: "coach_recommendation",
            columns: ["workout_session_id", "generated_at"]
        )
        try db.create(
            index: "idx_food_portion_preference_last_used",
            on: "food_portion_preference",
            columns: ["last_used_at"]
        )
        try db.create(
            index: "idx_pending_food_import_status_created",
            on: "pending_food_import",
            columns: ["status", "created_at"]
        )
    }
}
