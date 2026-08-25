import Foundation
import GRDB

enum DailyMetricsV19SchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v19_daily_metrics_step_resting") { db in
            try db.alter(table: "daily_metrics") { table in
                table.add(column: "step_count", .integer)
                table.add(column: "resting_energy_kcal", .double)
            }
        }
    }
}