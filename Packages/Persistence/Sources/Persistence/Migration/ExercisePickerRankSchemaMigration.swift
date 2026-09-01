import GRDB

enum ExercisePickerRankSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v21_exercise_picker_rank") { db in
            try db.alter(table: "exercise") { table in
                table.add(column: "picker_rank", .integer).notNull().defaults(to: CatalogPickerCurator.unrankedPickerRank)
            }
        }
    }
}
