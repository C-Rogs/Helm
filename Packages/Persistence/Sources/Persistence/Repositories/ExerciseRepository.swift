import Core
import Foundation
import GRDB

public struct ExerciseRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func upsert(
        id: String,
        canonicalName: String,
        displayName: String,
        exerciseMode: ExerciseMode,
        isCustom: Bool = false,
        primaryMuscleGroup: String? = nil,
        isPickerDefault: Bool = false,
        timestamp: Date = Date()
    ) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO exercise (
                        id, canonical_name, display_name, exercise_mode, primary_muscle_group,
                        secondary_muscle_groups_json, is_custom, sort_name, is_picker_default,
                        is_hevy_library, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, '[]', ?, ?, ?, 0, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        canonical_name = excluded.canonical_name,
                        display_name = excluded.display_name,
                        exercise_mode = excluded.exercise_mode,
                        primary_muscle_group = excluded.primary_muscle_group,
                        is_custom = excluded.is_custom,
                        sort_name = excluded.sort_name,
                        is_picker_default = excluded.is_picker_default,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    id,
                    canonicalName,
                    displayName,
                    exerciseMode.rawValue,
                    primaryMuscleGroup,
                    isCustom ? 1 : 0,
                    displayName.lowercased(),
                    isPickerDefault ? 1 : 0,
                    now,
                    now
                ]
            )
        }
    }

    public func addAlias(id: String, exerciseID: String, alias: String, timestamp: Date = Date()) throws {
        let normalized = alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO exercise_alias (id, exercise_id, alias, normalized_alias, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO NOTHING
                    """,
                arguments: [id, exerciseID, alias, normalized, now]
            )
        }
    }

    public func fetchSummary(id: String) throws -> ExerciseSummary? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, display_name, exercise_mode, is_custom, primary_muscle_group
                    FROM exercise
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [id]
            ) else {
                return nil
            }
            return try Self.summary(from: row)
        }
    }

    public func resolveExerciseID(normalizedAlias: String) throws -> String? {
        try pool.read { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT exercise_id
                    FROM exercise_alias
                    WHERE normalized_alias = ?
                    LIMIT 1
                    """,
                arguments: [normalizedAlias]
            )
        }
    }

    private static func summary(from row: Row) throws -> ExerciseSummary {
        guard let modeRaw: String = row["exercise_mode"],
              let mode = ExerciseMode(rawValue: modeRaw) else {
            throw PersistenceError.migrationFailed("invalid exercise_mode")
        }
        let isCustom = (row["is_custom"] as Int?) == 1
        return ExerciseSummary(
            id: row["id"],
            displayName: row["display_name"],
            exerciseMode: mode,
            isCustom: isCustom,
            primaryMuscleGroup: row["primary_muscle_group"]
        )
    }
}
