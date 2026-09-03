import Foundation
import GRDB

enum ScheduleOverrideSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v26_schedule_override") { db in
            try db.create(table: "schedule_override") { table in
                table.column("id", .integer).primaryKey()
                table.column("overrides_json", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
        }
    }
}
