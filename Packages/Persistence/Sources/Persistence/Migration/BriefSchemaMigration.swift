import Foundation
import GRDB

enum BriefSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v9_daily_brief") { db in
            try db.create(table: "daily_brief") { table in
                table.column("helm_day", .text).primaryKey()
                table.column("input_fingerprint", .text).notNull()
                table.column("engine_text", .text).notNull()
                table.column("narration_text", .text).notNull()
                table.column("citation_ids_json", .text).notNull()
                table.column("source", .text).notNull()
                table.column("prompt_version", .text)
                table.column("schema_version", .text)
                table.column("updated_at", .text).notNull()
            }
        }
    }
}
