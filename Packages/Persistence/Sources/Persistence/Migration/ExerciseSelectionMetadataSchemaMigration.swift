import GRDB

enum ExerciseSelectionMetadataSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v23_exercise_selection_metadata") { db in
            try db.alter(table: "exercise") { table in
                table.add(column: "movement_pattern", .text)
                table.add(column: "evidence_json", .text)
            }
        }
    }
}
