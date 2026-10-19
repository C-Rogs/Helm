import GRDB

enum CoachChatConfirmationSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v29_coach_chat_confirmation") { db in
            try db.create(table: "coach_chat_confirmation") { table in
                table.column("id", .text).primaryKey()
                table.column("message_id", .text).notNull().indexed()
                table.column("title", .text).notNull()
                table.column("detail", .text).notNull()
                table.column("reason", .text)
                table.column("confirm_label", .text).notNull()
                table.column("cancel_label", .text).notNull()
                table.column("outcome", .text).notNull()
                table.column("selected_label", .text)
                table.column("created_at", .text).notNull()
                table.column("resolved_at", .text)
            }
        }
    }
}
