import GRDB

enum NutritionDayDemandSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v20_nutrition_day_demand") { db in
            try db.create(table: "nutrition_day_demand_override") { table in
                table.column("helm_day", .text).primaryKey()
                table.column("demand", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
        }
    }
}
