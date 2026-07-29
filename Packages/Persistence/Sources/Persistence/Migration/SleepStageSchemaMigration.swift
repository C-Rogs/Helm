import Core
import GRDB

enum SleepStageSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v12_sleep_stage") { db in
            try db.alter(table: "sleep_record") { table in
                table.add(column: "stage", .text).notNull().defaults(to: SleepAnalysisStage.asleepUnspecified.rawValue)
            }
        }
    }
}
