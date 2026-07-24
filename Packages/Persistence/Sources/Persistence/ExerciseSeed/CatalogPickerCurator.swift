import Foundation
import GRDB

/// Picks picker-default exercises for the manual exercise picker.
enum CatalogPickerCurator {
    private static let targetDefaultCount = 220
    private static let maxPerMuscleEquipment = 4

    private static let stapleSubstrings: [String] = [
        "barbell bench press", "bench press", "incline bench press", "squat", "deadlift",
        "romanian deadlift", "overhead press", "shoulder press", "pull-up", "pull up",
        "chin-up", "lat pulldown", "barbell row", "dumbbell row", "leg press", "lunge",
        "hip thrust", "barbell curl", "dumbbell curl", "hammer curl", "tricep pushdown",
        "skull crusher", "calf raise", "plank", "crunch", "leg curl", "leg extension",
        "face pull", "lateral raise", "side lateral raise", "machine chest press",
        "machine bench press", "chest press", "tricep pushdown", "triceps pushdown",
        "cable triceps", "dumbbell bicep curl", "chest fly", "push-up", "dip", "farmer",
        "shrug", "good morning", "glute bridge", "running", "cycling", "rowing machine", "treadmill",
    ]

    struct CuratorRow: Sendable {
        let id: String
        let canonicalName: String
        let equipment: CatalogEquipment
        let primaryMuscleSlug: String?
        let movementPattern: CatalogMovementPattern
        let isHevyLibrary: Bool
    }

    static func apply(
        in db: Database,
        curation: ExercisePickerCuration = .algorithmic,
        explicitPickerIDs: Set<String> = []
    ) throws {
        switch curation {
        case .explicit:
            try applyExplicit(in: db, pickerIDs: explicitPickerIDs)
        case .algorithmic:
            try applyAlgorithmic(in: db)
        }
    }

    private static func applyExplicit(in db: Database, pickerIDs: Set<String>) throws {
        try db.execute(sql: "UPDATE exercise SET is_picker_default = 0 WHERE deleted_at IS NULL")
        for id in pickerIDs {
            try db.execute(
                sql: "UPDATE exercise SET is_picker_default = 1 WHERE id = ? AND deleted_at IS NULL",
                arguments: [id]
            )
        }
    }

    private static func applyAlgorithmic(in db: Database) throws {
        let rows = try fetchRows(db)
        let hevyIDs = Set(rows.filter(\.isHevyLibrary).map(\.id))

        try db.execute(sql: "UPDATE exercise SET is_picker_default = 0 WHERE deleted_at IS NULL")
        try db.execute(
            sql: "UPDATE exercise SET is_picker_default = 1 WHERE deleted_at IS NULL AND is_hevy_library = 1"
        )

        var selected = hevyIDs
        var bucketCounts: [String: Int] = [:]

        let scored = rows
            .filter { !hevyIDs.contains($0.id) }
            .map { ($0, score($0)) }
            .sorted { $0.1 > $1.1 }

        for (row, scoreValue) in scored where scoreValue > 0 {
            guard selected.count < targetDefaultCount else { break }
            let bucketKey = bucketKey(for: row)
            let count = bucketCounts[bucketKey, default: 0]
            guard count < maxPerMuscleEquipment else { continue }
            if isNearDuplicate(row, among: rows.filter { selected.contains($0.id) }) {
                continue
            }
            selected.insert(row.id)
            bucketCounts[bucketKey] = count + 1
        }

        if selected.count < 120 {
            for row in rows where !selected.contains(row.id) {
                guard selected.count < targetDefaultCount else { break }
                guard row.equipment != .other else { continue }
                let bucketKey = bucketKey(for: row)
                let count = bucketCounts[bucketKey, default: 0]
                guard count < maxPerMuscleEquipment else { continue }
                selected.insert(row.id)
                bucketCounts[bucketKey] = count + 1
            }
        }

        for id in selected where !hevyIDs.contains(id) {
            try db.execute(
                sql: "UPDATE exercise SET is_picker_default = 1 WHERE id = ? AND deleted_at IS NULL",
                arguments: [id]
            )
        }
    }

    private static func fetchRows(_ db: Database) throws -> [CuratorRow] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT id, canonical_name, display_name, equipment_type, primary_muscle_group, is_hevy_library
                FROM exercise
                WHERE deleted_at IS NULL
                """
        ).map { row in
            let canonical: String = row["canonical_name"]
            let equipmentRaw: String? = row["equipment_type"]
            let equipment = CatalogEquipment(rawValue: equipmentRaw ?? "") ?? .other
            let pattern = inferPattern(canonicalName: canonical, equipment: equipment)
            return CuratorRow(
                id: row["id"],
                canonicalName: canonical,
                equipment: equipment,
                primaryMuscleSlug: row["primary_muscle_group"],
                movementPattern: pattern,
                isHevyLibrary: (row["is_hevy_library"] as Int?) == 1
            )
        }
    }

    private static func inferPattern(canonicalName: String, equipment: CatalogEquipment) -> CatalogMovementPattern {
        let fake = FreeExerciseDBRecord(
            id: "",
            name: canonicalName,
            force: nil,
            level: nil,
            mechanic: nil,
            equipment: equipment.rawValue,
            primaryMuscles: [],
            secondaryMuscles: [],
            instructions: nil,
            category: nil,
            images: nil
        )
        return CatalogMovementPatternInferrer.infer(record: fake)
    }

    private static func score(_ row: CuratorRow) -> Int {
        let name = row.canonicalName.lowercased()
        var value = 0
        if stapleSubstrings.contains(where: { name.contains($0) }) {
            value += 40
        }
        switch row.equipment {
        case .barbell, .dumbbell, .machine, .cable, .bodyweight:
            value += 12
        case .kettlebell, .band, .smith:
            value += 6
        case .other:
            value += 0
        }
        if row.movementPattern == .cardio {
            value += 8
        }
        if name.contains("variation") || name.contains("alternate") {
            value -= 20
        }
        if name.filter({ $0 == "(" }).count > 1 {
            value -= 8
        }
        return value
    }

    private static func bucketKey(for row: CuratorRow) -> String {
        let muscle = row.primaryMuscleSlug ?? "unknown"
        return "\(muscle)-\(row.equipment.rawValue)"
    }

    private static func normalizedName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: "dumbbell", with: "")
            .replacingOccurrences(of: "barbell", with: "")
            .replacingOccurrences(of: "cable", with: "")
            .replacingOccurrences(of: "machine", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    private static func isNearDuplicate(_ row: CuratorRow, among selected: [CuratorRow]) -> Bool {
        let key = normalizedName(row.canonicalName)
        return selected.contains { normalizedName($0.canonicalName) == key }
    }
}
