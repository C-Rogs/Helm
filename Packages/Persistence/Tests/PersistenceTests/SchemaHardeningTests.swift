import Foundation
import GRDB
import Testing
@testable import Persistence

@Suite("Schema hardening v15")
struct SchemaHardeningTests {
    @Test("soft-deleted set_index can be reused")
    func softDeletedSetIndexReusable() throws {
        let pool = try DatabaseFactory.makeInMemoryPool()
        try AppMigrator().migrate(pool)

        let now = "2026-08-03T12:00:00.000Z"
        let exerciseID = "ex-1"
        let sessionID = "ws-1"
        let wseID = "wse-1"

        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO exercise (
                        id, canonical_name, display_name, exercise_mode, secondary_muscle_groups_json,
                        is_custom, sort_name, is_picker_default, is_hevy_library, created_at, updated_at
                    ) VALUES (?, 'bench', 'Bench', 'reps_weight', '[]', 0, 'bench', 1, 0, ?, ?)
                    """,
                arguments: [exerciseID, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO workout_session (
                        id, started_at, status, source, total_volume_kg_cache,
                        total_set_count_cache, total_rep_count_cache, created_at, updated_at
                    ) VALUES (?, ?, 'active', 'manual', 0, 0, 0, ?, ?)
                    """,
                arguments: [sessionID, now, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO workout_session_exercise (
                        id, workout_session_id, exercise_id, display_order, exercise_mode,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, 0, 'reps_weight', ?, ?)
                    """,
                arguments: [wseID, sessionID, exerciseID, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, logged_exercise_id, set_index, set_type,
                        status, created_at, updated_at, deleted_at
                    ) VALUES ('set-old', ?, ?, 0, 'normal', 'planned', ?, ?, ?)
                    """,
                arguments: [wseID, exerciseID, now, now, now]
            )
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, logged_exercise_id, set_index, set_type,
                        status, created_at, updated_at
                    ) VALUES ('set-new', ?, ?, 0, 'normal', 'planned', ?, ?)
                    """,
                arguments: [wseID, exerciseID, now, now]
            )
        }

        let liveCount = try pool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM set_entry
                    WHERE workout_session_exercise_id = ? AND set_index = 0 AND deleted_at IS NULL
                    """,
                arguments: [wseID]
            ) ?? 0
        }
        #expect(liveCount == 1)
    }

    @Test("v15 indexes exist after migrate")
    func v15IndexesExist() throws {
        let pool = try DatabaseFactory.makeInMemoryPool()
        try AppMigrator().migrate(pool)

        let expected = [
            "idx_set_entry_active_set_index",
            "idx_set_entry_logged_exercise",
            "idx_workout_session_status_deleted_started",
            "idx_workout_block_session",
            "idx_sleep_record_overlap",
            "idx_coach_recommendation_session",
            "idx_food_portion_preference_last_used",
            "idx_pending_food_import_status_created"
        ]

        try pool.read { db in
            for name in expected {
                let exists = try Bool.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) > 0
                        FROM sqlite_master
                        WHERE type = 'index' AND name = ?
                        """,
                    arguments: [name]
                ) ?? false
                #expect(exists, "missing index \(name)")
            }

            let oldStatusIndexGone = try Bool.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) = 0
                    FROM sqlite_master
                    WHERE type = 'index' AND name = 'idx_workout_session_status'
                    """
            ) ?? false
            #expect(oldStatusIndexGone)
        }
    }
}
