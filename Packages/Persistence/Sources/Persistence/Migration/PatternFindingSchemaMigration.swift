import Foundation
import GRDB

enum PatternFindingSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v27_pattern_finding") { db in
            try db.create(table: "pattern_finding") { table in
                table.column("id", .text).primaryKey()
                table.column("ast_json", .text).notNull()
                table.column("status", .text).notNull()
                table.column("verdict", .text).notNull()
                table.column("n_exp", .integer).notNull()
                table.column("n_ctrl", .integer).notNull()
                table.column("cliffs_delta", .double)
                table.column("median_delta", .double)
                table.column("permutation_p", .double)
                table.column("fdr_q", .double)
                table.column("ci_low", .double)
                table.column("ci_high", .double)
                table.column("copy_register", .text).notNull()
                table.column("headline", .text).notNull()
                table.column("body", .text).notNull()
                table.column("first_detected_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.column("posterior_mu", .double)
                table.column("posterior_sigma", .double)
                table.column("e_value", .double)
            }
            try db.create(index: "idx_pattern_finding_status", on: "pattern_finding", columns: ["status"])

            try db.create(table: "pattern_fdr_state") { table in
                table.column("id", .integer).primaryKey()
                table.column("wealth0", .double).notNull()
                table.column("alpha_earn", .double).notNull()
                table.column("test_index", .integer).notNull()
                table.column("rejection_times_json", .text).notNull()
                table.column("spent_ids_json", .text).notNull()
                table.column("last_discovery_at", .text)
                table.column("updated_at", .text).notNull()
            }

            try db.alter(table: "nutrition_day") { table in
                table.add(column: "eat_to_kcal", .double)
            }
            try db.alter(table: "workout_session") { table in
                table.add(column: "prescribed_working_sets", .integer)
                table.add(column: "prescribed_volume_kg", .double)
            }
        }
    }
}
