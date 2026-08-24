import Foundation
import GRDB

enum PlanBuilderSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v18_plan_builder_session") { db in
            try db.create(table: "plan_builder_session") { table in
                table.column("id", .integer).primaryKey()
                table.column("session_json", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
        }
    }
}
