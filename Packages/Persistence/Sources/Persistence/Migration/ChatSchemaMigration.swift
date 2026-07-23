import Foundation
import GRDB

enum ChatSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v7_chat") { db in
            try db.create(table: "chat_message") { table in
                table.column("id", .text).primaryKey()
                table.column("role", .text).notNull()
                table.column("text", .text).notNull()
                table.column("prompt_version", .text).notNull()
                table.column("schema_version", .text)
                table.column("created_at", .text).notNull()
                table.column("sort_index", .integer).notNull()
            }
            try db.create(
                index: "idx_chat_message_sort_index",
                on: "chat_message",
                columns: ["sort_index"]
            )
        }
    }
}
