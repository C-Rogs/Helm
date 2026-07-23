import Foundation
import GRDB

enum PhaseGoalSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v8_phase_goal") { db in
            try db.create(table: "training_plan_settings") { table in
                table.column("id", .integer).primaryKey()
                table.column("settings_json", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
        }
    }
}
