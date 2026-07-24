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

    public func listForPicker(search: String? = nil, limit: Int = 200) throws -> [ExerciseSummary] {
        try listForPicker(search: search, muscleGroup: nil, limit: limit)
    }

    public func listForPicker(
        search: String?,
        muscleGroup: String?,
        limit: Int = 500
    ) throws -> [ExerciseSummary] {
        try pool.read { db in
            var sql = """
                SELECT id, display_name, exercise_mode, is_custom, primary_muscle_group
                FROM exercise
                WHERE deleted_at IS NULL
                """
            var arguments: [DatabaseValueConvertible] = []
            if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sql += " AND (display_name LIKE ? OR canonical_name LIKE ?)"
                let pattern = "%\(search.trimmingCharacters(in: .whitespacesAndNewlines))%"
                arguments.append(contentsOf: [pattern, pattern])
            }
            if let muscleGroup, !muscleGroup.isEmpty {
                sql += " AND primary_muscle_group = ?"
                arguments.append(muscleGroup)
            }
            sql += """
                 ORDER BY is_picker_default DESC, is_custom ASC, sort_name ASC
                 LIMIT ?
                """
            arguments.append(limit)

            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                .map { try Self.summary(from: $0) }
        }
    }

    public func listRecentlyUsed(limit: Int = 12) throws -> [ExerciseSummary] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT e.id, e.display_name, e.exercise_mode, e.is_custom, e.primary_muscle_group
                    FROM exercise e
                    INNER JOIN workout_session_exercise wse ON wse.exercise_id = e.id
                    INNER JOIN workout_session ws ON ws.id = wse.workout_session_id
                    WHERE e.deleted_at IS NULL
                      AND ws.deleted_at IS NULL
                      AND ws.status = 'completed'
                    GROUP BY e.id
                    ORDER BY MAX(ws.ended_at) DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            )
            return try rows.map { try Self.summary(from: $0) }
        }
    }

    public func listMuscleGroups() throws -> [String] {
        try pool.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT primary_muscle_group
                    FROM exercise
                    WHERE deleted_at IS NULL
                      AND primary_muscle_group IS NOT NULL
                      AND primary_muscle_group != ''
                    ORDER BY primary_muscle_group ASC
                    """
            )
        }
    }

    public func fetchCatalogRows(limit: Int = 2_000) throws -> [ExerciseCatalogRow] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, display_name, primary_muscle_group, secondary_muscle_groups_json,
                           equipment_type, is_picker_default
                    FROM exercise
                    WHERE deleted_at IS NULL AND is_picker_default = 1
                    ORDER BY sort_name ASC
                    LIMIT ?
                    """,
                arguments: [limit]
            )

            return try rows.map { row in
                let secondaryJSON: String = row["secondary_muscle_groups_json"] ?? "[]"
                let secondaries = try Self.decodeStringArray(from: secondaryJSON)
                return ExerciseCatalogRow(
                    id: row["id"],
                    displayName: row["display_name"],
                    primaryMuscleGroup: row["primary_muscle_group"],
                    secondaryMuscleGroups: secondaries,
                    equipment: row["equipment_type"],
                    isPickerDefault: (row["is_picker_default"] as Int?) == 1
                )
            }
        }
    }

    public func displayNames(for exerciseIDs: [String]) throws -> [String: String] {
        guard !exerciseIDs.isEmpty else { return [:] }
        return try pool.read { db in
            let placeholders = Array(repeating: "?", count: exerciseIDs.count).joined(separator: ", ")
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, display_name
                    FROM exercise
                    WHERE deleted_at IS NULL AND id IN (\(placeholders))
                    """,
                arguments: StatementArguments(exerciseIDs)
            )
            var names: [String: String] = [:]
            for row in rows {
                names[row["id"]] = row["display_name"]
            }
            return names
        }
    }

    public func exerciseCount() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM exercise WHERE deleted_at IS NULL"
            ) ?? 0
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

    public func resolveImportedTitle(_ title: String) throws -> ResolvedImportedExerciseID? {
        let candidates = Self.importTitleCandidates(from: title)
        for candidate in candidates {
            if let exerciseID = try resolveExerciseID(normalizedAlias: candidate) {
                return ResolvedImportedExerciseID(exerciseID: exerciseID, matchKind: .alias)
            }

            if let exerciseID = try resolveExerciseByCanonicalName(candidate) {
                return ResolvedImportedExerciseID(exerciseID: exerciseID, matchKind: .displayName)
            }
        }
        return nil
    }

    private func resolveExerciseByCanonicalName(_ normalized: String) throws -> String? {
        try pool.read { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT id
                    FROM exercise
                    WHERE deleted_at IS NULL
                      AND (lower(display_name) = ? OR lower(canonical_name) = ?)
                    LIMIT 1
                    """,
                arguments: [normalized, normalized]
            )
        }
    }

    private static func importTitleCandidates(from title: String) -> [String] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = ParsedWorkoutTitle.catalogMatchTitle(from: trimmed)
        let values = [trimmed, stripped]
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
    }

    private static func decodeStringArray(from json: String) throws -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([String].self, from: data)
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
