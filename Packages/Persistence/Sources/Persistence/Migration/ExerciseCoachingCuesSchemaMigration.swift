import GRDB

enum ExerciseCoachingCuesSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v13_exercise_coaching_cues") { db in
            try db.alter(table: "exercise") { table in
                table.add(column: "coaching_cues_json", .text).notNull().defaults(to: "[]")
            }
        }
    }
}
