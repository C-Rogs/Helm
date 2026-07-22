import Foundation
import GRDB

enum ReadinessSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3_readiness_schema") { db in
            try db.create(table: "readiness_daily_score") { table in
                table.column("helm_day", .text).primaryKey()
                table.column("score_json", .text).notNull()
                table.column("computed_at", .text).notNull()
            }

            try db.create(table: "readiness_baseline_state") { table in
                table.column("id", .integer).primaryKey()
                table.column("state_json", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
        }
    }
}
