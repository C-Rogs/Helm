import Foundation
import GRDB

enum NutritionLogStatusSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v11_nutrition_day_log_status") { db in
            try db.create(table: "nutrition_day_log_status") { table in
                table.column("helm_day", .text).primaryKey()
                table.column("logging_complete", .integer).notNull().defaults(to: 0)
                table.column("marked_at", .text).notNull()
            }
        }
    }
}
