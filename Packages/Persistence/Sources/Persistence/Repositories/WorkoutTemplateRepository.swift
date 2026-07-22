import Core
import Foundation
import GRDB

public struct WorkoutTemplateRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func insert(_ draft: WorkoutTemplateDraft, timestamp: Date = Date()) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO workout_template (id, name, notes, display_order, created_at, updated_at)
                    VALUES (?, ?, ?, 0, ?, ?)
                    """,
                arguments: [draft.id, draft.name, draft.notes, now, now]
            )

            for exercise in draft.exercises {
                try db.execute(
                    sql: """
                        INSERT INTO workout_template_exercise (
                            id, workout_template_id, exercise_id, display_order,
                            target_set_count, target_rep_min, target_rep_max, target_weight_kg,
                            default_rest_seconds, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        exercise.id,
                        draft.id,
                        exercise.exerciseID,
                        exercise.displayOrder,
                        exercise.targetSetCount,
                        exercise.targetRepMin,
                        exercise.targetRepMax,
                        exercise.targetMass?.kilograms,
                        exercise.defaultRestSeconds,
                        now,
                        now
                    ]
                )
            }
        }
    }

    public func fetchSummaries() throws -> [WorkoutTemplateSummary] {
        try pool.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, name, notes
                    FROM workout_template
                    WHERE deleted_at IS NULL
                    ORDER BY display_order ASC, name COLLATE NOCASE ASC
                    """
            ).map { row in
                WorkoutTemplateSummary(
                    id: row["id"],
                    name: row["name"],
                    notes: row["notes"]
                )
            }
        }
    }

    public func fetch(id: String) throws -> WorkoutTemplateDraft? {
        try pool.read { db in
            guard let template = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, name, notes
                    FROM workout_template
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [id]
            ) else {
                return nil
            }

            let exercises = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, exercise_id, display_order, target_set_count, target_rep_min,
                           target_rep_max, target_weight_kg, default_rest_seconds
                    FROM workout_template_exercise
                    WHERE workout_template_id = ? AND deleted_at IS NULL
                    ORDER BY display_order ASC
                    """,
                arguments: [id]
            ).map { row in
                WorkoutTemplateExerciseDraft(
                    id: row["id"],
                    exerciseID: row["exercise_id"],
                    displayOrder: row["display_order"],
                    targetSetCount: row["target_set_count"],
                    targetRepMin: row["target_rep_min"],
                    targetRepMax: row["target_rep_max"],
                    targetMass: (row["target_weight_kg"] as Double?).map { Mass(kilograms: $0) },
                    defaultRestSeconds: row["default_rest_seconds"]
                )
            }

            return WorkoutTemplateDraft(
                id: template["id"],
                name: template["name"],
                notes: template["notes"],
                exercises: exercises
            )
        }
    }
}
