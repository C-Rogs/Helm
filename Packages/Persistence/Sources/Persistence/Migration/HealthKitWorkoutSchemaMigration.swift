import Foundation
import GRDB

enum HealthKitWorkoutSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v17_health_kit_workout") { db in
            try db.alter(table: "workout_session") { table in
                table.add(column: "hk_uuid", .text)
                table.add(column: "activity_type", .text)
                table.add(column: "active_energy_kcal", .double)
                table.add(column: "distance_meters", .double)
                table.add(column: "source_bundle_id", .text)
            }
            try db.create(
                index: "idx_workout_session_hk_uuid",
                on: "workout_session",
                columns: ["hk_uuid"],
                unique: true,
                condition: SQL("hk_uuid IS NOT NULL")
            )
        }
    }
}