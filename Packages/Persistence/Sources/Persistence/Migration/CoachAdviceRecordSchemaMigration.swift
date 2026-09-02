import GRDB

enum CoachAdviceRecordSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v24_coach_advice_record") { db in
            try db.create(table: "coach_advice_record") { table in
                table.column("id", .text).primaryKey()
                table.column("message_id", .text).notNull().indexed()
                table.column("advice_type", .text).notNull()
                table.column("schema_version", .text).notNull()
                table.column("prescribed_payload", .text).notNull()
                table.column("state", .text).notNull()
                table.column("linked_session_id", .text)
                table.column("helm_day", .text).notNull().indexed()
                table.column("created_at", .text).notNull()
            }
            try db.create(
                index: "idx_coach_advice_record_type_state",
                on: "coach_advice_record",
                columns: ["advice_type", "state"]
            )
        }
    }
}
