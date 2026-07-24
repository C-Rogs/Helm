import Core
import Foundation
import GRDB

enum FoodLoggingSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v10_food_logging") { db in
            try db.alter(table: "meal") { table in
                table.add(column: "bucket", .text).notNull().defaults(to: MealBucket.snacks.rawValue)
            }

            try db.create(table: "meal_line_item") { table in
                table.column("id", .text).primaryKey()
                table.column("meal_id", .text).notNull()
                    .references("meal", onDelete: .cascade)
                table.column("food_origin", .text).notNull()
                table.column("food_external_id", .text).notNull()
                table.column("food_display_name", .text).notNull()
                table.column("grams", .double).notNull()
                table.column("serving_label", .text)
                table.column("energy_kcal", .double).notNull()
                table.column("protein_grams", .double).notNull()
                table.column("carbohydrate_grams", .double).notNull()
                table.column("fat_grams", .double).notNull()
                table.column("sort_order", .integer).notNull()
            }
            try db.create(index: "idx_meal_line_item_meal_id", on: "meal_line_item", columns: ["meal_id"])

            try db.create(table: "food_product_cache") { table in
                table.column("food_ref_key", .text).primaryKey()
                table.column("food_origin", .text).notNull()
                table.column("food_external_id", .text).notNull()
                table.column("display_name", .text).notNull()
                table.column("per_100g_kcal", .double).notNull()
                table.column("per_100g_protein", .double).notNull()
                table.column("per_100g_carbs", .double).notNull()
                table.column("per_100g_fat", .double).notNull()
                table.column("snapshot_json", .text)
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "food_portion_preference") { table in
                table.column("food_ref_key", .text).primaryKey()
                table.column("food_origin", .text).notNull()
                table.column("food_external_id", .text).notNull()
                table.column("food_display_name", .text).notNull()
                table.column("grams", .double).notNull()
                table.column("serving_label", .text)
                table.column("last_used_at", .text).notNull()
            }

            try db.create(table: "meal_template") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("bucket", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "meal_template_item") { table in
                table.column("id", .text).primaryKey()
                table.column("meal_template_id", .text).notNull()
                    .references("meal_template", onDelete: .cascade)
                table.column("line_item_json", .text).notNull()
                table.column("sort_order", .integer).notNull()
            }
            try db.create(
                index: "idx_meal_template_item_template_id",
                on: "meal_template_item",
                columns: ["meal_template_id"]
            )

            try db.create(table: "pending_food_import") { table in
                table.column("id", .text).primaryKey()
                table.column("created_at", .text).notNull()
                table.column("barcode", .text)
                table.column("photo_meal_id", .text)
                table.column("provisional_line_items_json", .text).notNull().defaults(to: "[]")
                table.column("status", .text).notNull()
            }

            try db.create(table: "food_log_recent") { table in
                table.column("food_ref_key", .text).primaryKey()
                table.column("food_origin", .text).notNull()
                table.column("food_external_id", .text).notNull()
                table.column("food_display_name", .text).notNull()
                table.column("grams", .double).notNull()
                table.column("serving_label", .text)
                table.column("last_used_at", .text).notNull()
            }
            try db.create(
                index: "idx_food_log_recent_last_used",
                on: "food_log_recent",
                columns: ["last_used_at"]
            )
        }
    }
}
