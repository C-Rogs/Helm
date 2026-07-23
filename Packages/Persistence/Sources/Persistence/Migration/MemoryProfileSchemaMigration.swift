import Foundation
import GRDB

enum MemoryProfileSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v4_memory_profile") { db in
            try db.create(table: "memory_profile") { table in
                table.column("id", .integer).primaryKey()
                table.column("profile_json", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
        }
    }
}
