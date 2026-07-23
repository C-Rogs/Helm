import Foundation
import GRDB

public struct ExerciseSeedImporter: Sendable {
    public static let appliedVersionMetadataKey = "exercise_seed_version"

    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func appliedSeedVersion() throws -> Int {
        try pool.read { db in
            guard let value = try String.fetchOne(
                db,
                sql: "SELECT value FROM app_metadata WHERE key = ?",
                arguments: [Self.appliedVersionMetadataKey]
            ) else {
                return 0
            }
            return Int(value) ?? 0
        }
    }

    public func importIfNeeded(
        manifestURL: URL,
        manifestData: Data? = nil
    ) throws -> ExerciseSeedImportResult {
        let data = try manifestData ?? Data(contentsOf: manifestURL)
        let manifest = try ExerciseSeedLoader.loadManifest(from: data)
        let applied = try appliedSeedVersion()
        guard manifest.seedVersion > applied else {
            return ExerciseSeedImportResult(
                appliedSeedVersion: applied,
                importedCount: 0,
                skippedBecauseUpToDate: true
            )
        }

        let entries = try ExerciseSeedLoader.resolveEntries(
            manifest: manifest,
            manifestDirectory: manifestURL.deletingLastPathComponent()
        )
        let importedCount = try importEntries(entries, seedVersion: manifest.seedVersion)
        return ExerciseSeedImportResult(
            appliedSeedVersion: manifest.seedVersion,
            importedCount: importedCount,
            skippedBecauseUpToDate: false
        )
    }

    @discardableResult
    public func importEntries(_ entries: [ExerciseSeedEntry], seedVersion: Int) throws -> Int {
        let now = ISO8601Coding.string(from: Date())
        try pool.write { db in
            for entry in entries {
                try upsertSeedEntry(entry, now: now, in: db)
            }
            try CatalogPickerCurator.apply(in: db)
            try db.execute(
                sql: """
                    INSERT INTO app_metadata (key, value, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET
                        value = excluded.value,
                        updated_at = excluded.updated_at
                    """,
                arguments: [Self.appliedVersionMetadataKey, String(seedVersion), now]
            )
        }
        return entries.count
    }

    private func upsertSeedEntry(_ entry: ExerciseSeedEntry, now: String, in db: Database) throws {
        let secondaryJSON = try encodeJSON(entry.secondaryMuscleGroups)
        let isCustom = 0
        let isPickerDefault = (entry.isPickerDefault ?? false) ? 1 : 0
        let isHevyLibrary = (entry.isHevyLibrary ?? false) ? 1 : 0

        try db.execute(
            sql: """
                INSERT INTO exercise (
                    id, canonical_name, display_name, exercise_mode, equipment_type,
                    primary_muscle_group, secondary_muscle_groups_json, is_custom, sort_name,
                    instruction_text, gif_url, source_dataset_id, is_hevy_library, is_picker_default,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    canonical_name = excluded.canonical_name,
                    display_name = excluded.display_name,
                    exercise_mode = excluded.exercise_mode,
                    equipment_type = excluded.equipment_type,
                    primary_muscle_group = excluded.primary_muscle_group,
                    secondary_muscle_groups_json = excluded.secondary_muscle_groups_json,
                    instruction_text = COALESCE(excluded.instruction_text, exercise.instruction_text),
                    gif_url = COALESCE(excluded.gif_url, exercise.gif_url),
                    source_dataset_id = excluded.source_dataset_id,
                    is_hevy_library = MAX(exercise.is_hevy_library, excluded.is_hevy_library),
                    sort_name = excluded.sort_name,
                    updated_at = excluded.updated_at
                WHERE exercise.is_custom = 0
                """,
            arguments: [
                entry.id,
                entry.canonicalName,
                entry.displayName,
                entry.exerciseMode.rawValue,
                entry.equipment,
                entry.primaryMuscleGroup,
                secondaryJSON,
                isCustom,
                entry.displayName.lowercased(),
                entry.instructionText,
                entry.imageURL,
                entry.sourceDatasetID,
                isHevyLibrary,
                isPickerDefault,
                now,
                now,
            ]
        )

        try insertAliases(for: entry, now: now, in: db)
    }

    private func insertAliases(for entry: ExerciseSeedEntry, now: String, in db: Database) throws {
        var aliases = entry.aliases
        aliases.append(entry.displayName)
        aliases.append(entry.canonicalName)

        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let normalized = trimmed.lowercased()
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO exercise_alias (id, exercise_id, alias, normalized_alias, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, entry.id, trimmed, normalized, now]
            )
        }
    }

    private func encodeJSON(_ values: [String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: values)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
