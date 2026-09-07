import GRDB

enum ExerciseDemoURLSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v28_exercise_demo_url") { db in
            try db.alter(table: "exercise") { table in
                table.add(column: "demo_url", .text)
            }
        }
    }
}
