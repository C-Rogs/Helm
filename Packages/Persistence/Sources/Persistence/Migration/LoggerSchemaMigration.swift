import Foundation
import GRDB

enum LoggerSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2_logger_schema") { db in
            try db.create(table: "exercise") { table in
                table.column("id", .text).primaryKey()
                table.column("canonical_name", .text).notNull()
                table.column("display_name", .text).notNull()
                table.column("exercise_mode", .text).notNull()
                table.column("equipment_type", .text)
                table.column("primary_muscle_group", .text)
                table.column("secondary_muscle_groups_json", .text).notNull().defaults(to: "[]")
                table.column("is_custom", .integer).notNull().defaults(to: 0)
                table.column("sort_name", .text).notNull()
                table.column("instruction_text", .text)
                table.column("gif_url", .text)
                table.column("is_picker_default", .integer).notNull().defaults(to: 0)
                table.column("is_hevy_library", .integer).notNull().defaults(to: 0)
                table.column("source_dataset_id", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }

            try db.create(table: "exercise_alias") { table in
                table.column("id", .text).primaryKey()
                table.column("exercise_id", .text).notNull()
                    .references("exercise", onDelete: .cascade)
                table.column("alias", .text).notNull()
                table.column("normalized_alias", .text).notNull()
                table.column("created_at", .text).notNull()
            }
            try db.create(
                index: "idx_exercise_alias_unique",
                on: "exercise_alias",
                columns: ["exercise_id", "normalized_alias"],
                unique: true
            )
            try db.create(index: "idx_exercise_alias_normalized", on: "exercise_alias", columns: ["normalized_alias"])
            try db.create(
                index: "idx_exercise_picker",
                on: "exercise",
                columns: ["deleted_at", "is_picker_default", "is_custom"]
            )

            try db.create(table: "workout_session") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text)
                table.column("notes", .text)
                table.column("started_at", .text).notNull()
                table.column("ended_at", .text)
                table.column("status", .text).notNull()
                table.column("source", .text).notNull().defaults(to: "manual")
                table.column("total_duration_seconds_cache", .integer)
                table.column("total_volume_kg_cache", .double).notNull().defaults(to: 0)
                table.column("total_set_count_cache", .integer).notNull().defaults(to: 0)
                table.column("total_rep_count_cache", .integer).notNull().defaults(to: 0)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }
            try db.create(index: "idx_workout_session_status", on: "workout_session", columns: ["status", "started_at"])

            try db.create(table: "workout_block") { table in
                table.column("id", .text).primaryKey()
                table.column("workout_session_id", .text).notNull()
                    .references("workout_session", onDelete: .cascade)
                table.column("block_type", .text).notNull()
                table.column("display_order", .integer).notNull()
                table.column("external_superset_id", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "workout_session_exercise") { table in
                table.column("id", .text).primaryKey()
                table.column("workout_session_id", .text).notNull()
                    .references("workout_session", onDelete: .cascade)
                table.column("exercise_id", .text).notNull().references("exercise")
                table.column("block_id", .text).references("workout_block", onDelete: .setNull)
                table.column("display_order", .integer).notNull()
                table.column("notes", .text)
                table.column("exercise_mode", .text).notNull()
                table.column("target_rest_seconds", .integer)
                table.column("is_collapsed", .integer).notNull().defaults(to: 0)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }
            try db.create(
                index: "idx_workout_session_exercise_session_order",
                on: "workout_session_exercise",
                columns: ["workout_session_id", "display_order"]
            )
            try db.create(
                index: "idx_wse_exercise",
                on: "workout_session_exercise",
                columns: ["exercise_id", "deleted_at"]
            )

            try db.create(table: "set_entry") { table in
                table.column("id", .text).primaryKey()
                table.column("workout_session_exercise_id", .text).notNull()
                    .references("workout_session_exercise", onDelete: .cascade)
                table.column("logged_exercise_id", .text).references("exercise")
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
                table.uniqueKey(["workout_session_exercise_id", "set_index"])
            }
            try db.create(index: "idx_set_entry_exercise_order", on: "set_entry", columns: ["workout_session_exercise_id", "set_index"])
            try db.create(index: "idx_set_entry_completed", on: "set_entry", columns: ["status", "completed_at"])

            try db.create(table: "active_workout_state") { table in
                table.column("workout_session_id", .text).primaryKey()
                    .references("workout_session", onDelete: .cascade)
                table.column("current_workout_session_exercise_id", .text)
                    .references("workout_session_exercise", onDelete: .setNull)
                table.column("current_set_entry_id", .text).references("set_entry", onDelete: .setNull)
                table.column("focused_field", .text)
                table.column("paused_at", .text)
                table.column("autosave_revision", .integer).notNull().defaults(to: 0)
                table.column("recovery_state", .text).notNull()
                table.column("last_opened_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "rest_timer_state") { table in
                table.column("id", .text).primaryKey()
                table.column("workout_session_id", .text).notNull()
                    .references("workout_session", onDelete: .cascade)
                table.column("workout_session_exercise_id", .text)
                    .references("workout_session_exercise", onDelete: .setNull)
                table.column("source_set_entry_id", .text).references("set_entry", onDelete: .setNull)
                table.column("state", .text).notNull()
                table.column("started_at", .text)
                table.column("paused_at", .text)
                table.column("ends_at", .text)
                table.column("remaining_at_pause_seconds", .integer)
                table.column("default_duration_seconds", .integer).notNull().defaults(to: 0)
                table.column("user_adjusted_seconds", .integer).notNull().defaults(to: 0)
                table.column("auto_started", .integer).notNull().defaults(to: 1)
                table.column("last_action_at", .text).notNull()
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
            try db.create(
                index: "idx_rest_timer_state_session",
                on: "rest_timer_state",
                columns: ["workout_session_id", "last_action_at"]
            )
            try db.create(
                index: "idx_rest_timer_session_state",
                on: "rest_timer_state",
                columns: ["workout_session_id", "state"]
            )

            try db.create(table: "rest_timer_event") { table in
                table.column("id", .text).primaryKey()
                table.column("rest_timer_state_id", .text).notNull()
                    .references("rest_timer_state", onDelete: .cascade)
                table.column("event_type", .text).notNull()
                table.column("timestamp", .text).notNull()
                table.column("delta_seconds", .integer)
                table.column("source", .text).notNull()
                table.column("note", .text)
            }
            try db.create(
                index: "idx_rest_timer_event_timer",
                on: "rest_timer_event",
                columns: ["rest_timer_state_id", "timestamp"]
            )

            try db.create(table: "workout_template") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("notes", .text)
                table.column("folder_name", .text)
                table.column("display_order", .integer).notNull().defaults(to: 0)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }

            try db.create(table: "workout_template_exercise") { table in
                table.column("id", .text).primaryKey()
                table.column("workout_template_id", .text).notNull()
                    .references("workout_template", onDelete: .cascade)
                table.column("exercise_id", .text).notNull().references("exercise")
                table.column("block_key", .text)
                table.column("display_order", .integer).notNull()
                table.column("target_set_count", .integer)
                table.column("target_rep_min", .integer)
                table.column("target_rep_max", .integer)
                table.column("target_weight_kg", .double)
                table.column("target_duration_seconds", .integer)
                table.column("target_distance_km", .double)
                table.column("default_set_type", .text)
                table.column("default_rest_seconds", .integer)
                table.column("notes", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("deleted_at", .text)
            }
            try db.create(
                index: "idx_template_exercise_order",
                on: "workout_template_exercise",
                columns: ["workout_template_id", "display_order"]
            )

            try db.create(table: "personal_record") { table in
                table.column("id", .text).primaryKey()
                table.column("exercise_id", .text).notNull().references("exercise")
                table.column("metric_type", .text).notNull()
                table.column("metric_value", .double).notNull()
                table.column("source_set_entry_id", .text).references("set_entry", onDelete: .setNull)
                table.column("source_workout_session_id", .text).references("workout_session", onDelete: .setNull)
                table.column("achieved_at", .text).notNull()
                table.column("created_at", .text).notNull()
            }
            try db.create(
                index: "idx_personal_record_exercise_metric",
                on: "personal_record",
                columns: ["exercise_id", "metric_type", "achieved_at"]
            )

            try db.create(table: "exercise_history_snapshot") { table in
                table.column("exercise_id", .text).primaryKey()
                    .references("exercise", onDelete: .cascade)
                table.column("last_performed_at", .text)
                table.column("last_workout_session_id", .text).references("workout_session", onDelete: .setNull)
                table.column("last_completed_set_summary_json", .text)
                table.column("best_weight_kg", .double)
                table.column("best_estimated_1rm_kg", .double)
                table.column("lifetime_volume_kg", .double).notNull().defaults(to: 0)
                table.column("completed_set_count", .integer).notNull().defaults(to: 0)
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "coach_recommendation") { table in
                table.column("id", .text).primaryKey()
                table.column("scope", .text).notNull()
                table.column("workout_session_id", .text).references("workout_session", onDelete: .cascade)
                table.column("workout_session_exercise_id", .text)
                    .references("workout_session_exercise", onDelete: .cascade)
                table.column("set_entry_id", .text).references("set_entry", onDelete: .setNull)
                table.column("recommendation_type", .text).notNull()
                table.column("payload_json", .text).notNull()
                table.column("confidence", .double)
                table.column("model_version", .text)
                table.column("generated_at", .text).notNull()
                table.column("acted_on_at", .text)
                table.column("dismissed_at", .text)
            }
        }
    }
}
