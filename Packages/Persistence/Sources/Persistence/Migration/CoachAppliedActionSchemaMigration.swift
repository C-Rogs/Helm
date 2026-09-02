import GRDB

enum CoachAppliedActionSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v25_coach_applied_action") { db in
            try db.create(table: "coach_applied_action") { table in
                table.column("id", .text).primaryKey()
                table.column("message_id", .text).notNull().indexed()
                table.column("kind", .text).notNull()
                table.column("snapshot_json", .text).notNull()
                table.column("undone_at", .text)
                table.column("created_at", .text).notNull()
            }
        }
    }
}
