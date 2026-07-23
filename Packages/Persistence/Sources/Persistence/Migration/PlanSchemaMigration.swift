import Foundation
import GRDB

enum PlanSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v5_plan_schema") { db in
            try db.create(table: "plan_mesocycle_state") { table in
                table.column("id", .integer).primaryKey()
                table.column("state_json", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "planned_workout") { table in
                table.column("id", .text).primaryKey()
                table.column("helm_day", .text).notNull().indexed()
                table.column("status", .text).notNull()
                table.column("training_load", .double).notNull()
                table.column("session_json", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
        }
    }
}
