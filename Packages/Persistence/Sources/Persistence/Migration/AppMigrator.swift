import Foundation
import GRDB

struct AppMigrator {
    func migrate(_ writer: DatabaseWriter) throws {
        let migrator = Self.makeMigrator(upTo: SchemaVersion.latest)
        do {
            try migrator.migrate(writer)
        } catch {
            throw PersistenceError.migrationFailed(error.localizedDescription)
        }
    }

    static func makeMigrator(upTo version: Int) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        if version >= 1 {
            registerHealthSchema(on: &migrator)
        }
        if version >= 2 {
            LoggerSchemaMigration.register(on: &migrator)
        }
        if version >= 3 {
            ReadinessSchemaMigration.register(on: &migrator)
        }
        if version >= 4 {
            MemoryProfileSchemaMigration.register(on: &migrator)
        }
        if version >= 5 {
            PlanSchemaMigration.register(on: &migrator)
        }
        if version >= 6 {
            ExerciseSeedSchemaMigration.register(on: &migrator)
        }
        if version >= 7 {
            ChatSchemaMigration.register(on: &migrator)
        }
        if version >= 8 {
            PhaseGoalSchemaMigration.register(on: &migrator)
        }
        if version >= 9 {
            BriefSchemaMigration.register(on: &migrator)
        }
        if version >= 10 {
            FoodLoggingSchemaMigration.register(on: &migrator)
        }
        if version >= 11 {
            NutritionLogStatusSchemaMigration.register(on: &migrator)
        }
        if version >= 12 {
            SleepStageSchemaMigration.register(on: &migrator)
        }
        return migrator
    }

    static func registerHealthSchema(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_health_schema") { db in
            try db.create(table: "daily_metrics") { table in
                table.column("helm_day", .text).primaryKey()
                table.column("hrv_sdnn_ms", .integer)
                table.column("resting_heart_rate", .integer)
                table.column("respiratory_rate", .double)
                table.column("wrist_temperature_delta_celsius", .double)
                table.column("active_energy_kcal", .double)
                table.column("dietary_energy_kcal", .double)
                table.column("dietary_protein_grams", .double)
                table.column("dietary_carbohydrate_grams", .double)
                table.column("dietary_fat_grams", .double)
                table.column("prior_day_trimp", .double)
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "body_composition") { table in
                table.column("id", .text).primaryKey()
                table.column("helm_day", .text).notNull().indexed()
                table.column("mass_kg", .double).notNull()
                table.column("body_fat_percentage", .double)
                table.column("measured_at", .text).notNull()
            }
            try db.create(index: "idx_body_composition_measured_at", on: "body_composition", columns: ["measured_at"])

            try db.create(table: "sleep_record") { table in
                table.column("id", .text).primaryKey()
                table.column("helm_day", .text).notNull().indexed()
                table.column("start_at", .text).notNull()
                table.column("end_at", .text).notNull()
                table.column("source_bundle_id", .text)
            }

            try db.create(table: "nutrition_day") { table in
                table.column("helm_day", .text).primaryKey()
                table.column("total_energy_kcal", .double)
                table.column("total_protein_grams", .double)
                table.column("total_carbohydrate_grams", .double)
                table.column("total_fat_grams", .double)
                table.column("macro_gap_kcal", .double)
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "meal") { table in
                table.column("id", .text).primaryKey()
                table.column("helm_day", .text).notNull().indexed()
                table.column("name", .text).notNull()
                table.column("logged_at", .text).notNull()
                table.column("energy_kcal", .double)
                table.column("protein_grams", .double)
                table.column("carbohydrate_grams", .double)
                table.column("fat_grams", .double)
                table.column("source", .text).notNull()
                table.column("external_sample_id", .text)
            }
            try db.create(
                index: "idx_meal_external_sample_id",
                on: "meal",
                columns: ["external_sample_id"],
                unique: true,
                condition: SQL("external_sample_id IS NOT NULL")
            )
        }
    }
}
