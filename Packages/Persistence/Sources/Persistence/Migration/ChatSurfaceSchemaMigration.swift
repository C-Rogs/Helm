import GRDB

enum ChatSurfaceSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v22_chat_surface") { db in
            try db.alter(table: "chat_message") { table in
                table.add(column: "surface", .text).notNull().defaults(to: ChatSurface.chat.rawValue)
            }
            try db.create(
                index: "idx_chat_message_surface_sort_index",
                on: "chat_message",
                columns: ["surface", "sort_index"]
            )
        }
    }
}
