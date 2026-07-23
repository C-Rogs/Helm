import Core
import Foundation

enum CatalogEquipment: String, CaseIterable, Sendable {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight
    case kettlebell
    case band
    case smith
    case other
}

enum CatalogMovementPattern: String, Sendable {
    case squat
    case hinge
    case lunge
    case horizontalPush
    case verticalPush
    case horizontalPull
    case verticalPull
    case carry
    case isolation
    case cardio
    case core
}

enum CatalogEquipmentMapper {
    static func map(datasetEquipment: String?, exerciseName: String) -> CatalogEquipment {
        let nameLower = exerciseName.lowercased()
        if nameLower.contains("smith") {
            return .smith
        }
        guard let raw = datasetEquipment?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty
        else {
            return .other
        }
        switch raw {
        case "body only":
            return .bodyweight
        case "barbell", "e-z curl bar":
            return .barbell
        case "dumbbell":
            return .dumbbell
        case "machine":
            return .machine
        case "cable":
            return .cable
        case "kettlebells":
            return .kettlebell
        case "bands":
            return .band
        default:
            return .other
        }
    }

    static func hevyDisplayName(for equipment: CatalogEquipment) -> String {
        switch equipment {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .band: "Band"
        case .smith: "Smith Machine"
        case .other: "Other"
        }
    }

    static func storageValue(for equipment: CatalogEquipment) -> String {
        equipment.rawValue
    }
}

enum CatalogMuscleMapper {
    static func muscles(
        primary datasetPrimary: [String],
        secondary datasetSecondary: [String],
        exerciseName: String
    ) -> (primary: String?, secondaries: [String]) {
        let primary = datasetPrimary.compactMap { mapDatasetMuscle($0, exerciseName: exerciseName) }
        let secondary = datasetSecondary.compactMap { mapDatasetMuscle($0, exerciseName: exerciseName) }
        let primaryUnique = orderedUnique(primary)
        let secondaryUnique = orderedUnique(secondary.filter { !primaryUnique.contains($0) })
        return (primaryUnique.first, secondaryUnique)
    }

    private static func mapDatasetMuscle(_ raw: String, exerciseName: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let nameLower = exerciseName.lowercased()
        switch key {
        case "quadriceps":
            return "quadriceps"
        case "hamstrings":
            return "hamstrings"
        case "glutes":
            return "glutes"
        case "calves":
            return "calves"
        case "chest":
            return "chest"
        case "lats":
            return "lats"
        case "middle back":
            return "upper back"
        case "traps":
            return "traps"
        case "lower back":
            return "lower back"
        case "biceps":
            return "biceps"
        case "triceps":
            return "triceps"
        case "forearms":
            return "forearms"
        case "abdominals":
            if nameLower.contains("oblique") || nameLower.contains("side bend") {
                return "abs"
            }
            return "abs"
        case "abductors":
            return "abductors"
        case "adductors":
            return "adductors"
        case "neck":
            return "neck"
        case "shoulders":
            return "shoulders"
        default:
            return nil
        }
    }

    private static func orderedUnique(_ slugs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for slug in slugs where seen.insert(slug).inserted {
            result.append(slug)
        }
        return result
    }
}

enum CatalogTitleNormalizer: Sendable {
    static func normalize(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.precomposedStringWithCompatibilityMapping
        text = stripEmoji(text)
        let allowed = CharacterSet.alphanumerics.union(.whitespaces)
        text = String(text.unicodeScalars.map { scalar in
            if allowed.contains(scalar) {
                Character(scalar)
            } else {
                " "
            }
        })
        text = text.lowercased()
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text
    }

    private static func stripEmoji(_ text: String) -> String {
        text.filter { character in
            guard let scalar = character.unicodeScalars.first else { return true }
            return !scalar.properties.isEmojiPresentation && scalar.value < 0x1F000
        }
    }
}

enum CatalogMovementPatternInferrer {
    static func infer(record: FreeExerciseDBRecord) -> CatalogMovementPattern {
        let name = record.name.lowercased()
        let category = record.category?.lowercased() ?? ""
        let mechanic = record.mechanic?.lowercased() ?? ""

        if category == "cardio" || name.contains("running") || name.contains("treadmill") || name.contains("cycling") {
            return .cardio
        }
        if category == "plyometrics" && (name.contains("jump") || name.contains("sprint")) {
            return .cardio
        }
        if name.contains("plank") || name.contains("crunch") || name.contains("sit-up") || name.contains("sit up") {
            return .core
        }
        if name.contains("carry") || name.contains("farmer") {
            return .carry
        }
        if name.contains("lunge") || name.contains("split squat") || name.contains("step-up") || name.contains("step up") {
            return .lunge
        }
        if name.contains("squat") || name.contains("leg press") || name.contains("leg extension") {
            return .squat
        }
        if name.contains("deadlift") || name.contains("rdl") || name.contains("good morning") || name.contains("hip thrust") {
            return .hinge
        }
        if name.contains("pull-up") || name.contains("pull up") || name.contains("chin-up") || name.contains("chin up") {
            return .verticalPull
        }
        if name.contains("pulldown") || name.contains("pull down") || name.contains("lat pull") {
            return .verticalPull
        }
        if name.contains("row") && !name.contains("upright row") {
            return .horizontalPull
        }
        if name.contains("bench press") || name.contains("push-up") || name.contains("push up") {
            return .horizontalPush
        }
        if name.contains("fly") || name.contains("crossover") {
            return .horizontalPush
        }
        if name.contains("overhead press") || name.contains("shoulder press") || name.contains("military press") {
            return .verticalPush
        }
        if record.force?.lowercased() == "push" && mechanic == "compound" && name.contains("press") {
            return .verticalPush
        }
        if mechanic == "isolation" || category == "stretching" {
            return .isolation
        }
        if record.force?.lowercased() == "pull" && mechanic == "compound" {
            return .horizontalPull
        }
        if record.force?.lowercased() == "push" && mechanic == "compound" {
            return .horizontalPush
        }
        return .isolation
    }
}

enum CatalogExerciseModeInferrer {
    static func infer(record: FreeExerciseDBRecord, equipment: CatalogEquipment, pattern: CatalogMovementPattern) -> ExerciseMode {
        let name = record.name.lowercased()
        let category = record.category?.lowercased() ?? ""

        if pattern == .cardio || category == "cardio" {
            if name.contains("plank") || name.contains("hold") {
                return .duration
            }
            return .distanceDuration
        }
        if pattern == .core && (name.contains("plank") || name.contains("hold")) {
            return .duration
        }
        if equipment == .bodyweight
            && (name.contains("pull up") || name.contains("pull-up")
                || name.contains("chin up") || name.contains("chin-up")
                || name.contains("push up") || name.contains("push-up")
                || name.contains("dip"))
        {
            return .bodyweightReps
        }
        if equipment == .bodyweight && pattern == .core {
            return .bodyweightReps
        }
        return .weightReps
    }
}

enum CatalogAliasGenerator {
    static func hevyStyleTitle(canonicalName: String, equipment: CatalogEquipment) -> String? {
        let display = CatalogEquipmentMapper.hevyDisplayName(for: equipment)
        guard display != "Other", display != "Bodyweight" else { return nil }

        let prefixes = [
            "Barbell ", "Dumbbell ", "Cable ", "Machine ", "Kettlebell ", "Band ", "Smith Machine ",
        ]
        var base = canonicalName
        for prefix in prefixes where base.hasPrefix(prefix) {
            base = String(base.dropFirst(prefix.count))
            break
        }
        guard !base.isEmpty else { return nil }
        return "\(base) (\(display))"
    }

    static func simplifiedHevyAliases(from hevyTitle: String) -> [String] {
        let trimmed = hevyTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.lastIndex(of: "("), trimmed.hasSuffix(")") else { return [] }
        var base = String(trimmed[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(trimmed[open...])
        if let dash = base.range(of: " - ") {
            base = String(base[..<dash.lowerBound])
        }
        let simplified = "\(base) \(suffix)"
        var results = [simplified]
        if base.hasSuffix("s"), base.count > 3 {
            let singularBase = String(base.dropLast())
            results.append("\(singularBase) \(suffix)")
        }
        return results
    }

    static func geminiStyleAliases(canonicalName: String, equipment: CatalogEquipment) -> [String] {
        var aliases: [String] = []
        let canonicalLower = canonicalName.lowercased()

        if canonicalLower == "side lateral raise" {
            aliases.append(contentsOf: [
                "Dumbbell Lateral Raise",
                "Lateral Raise (Dumbbell)",
                "DB Lateral Raise",
            ])
        }
        if canonicalLower == "machine bench press" || canonicalLower == "leverage chest press" {
            aliases.append(contentsOf: [
                "Machine Chest Press",
                "Chest Press (Machine)",
                "Press Machine",
            ])
        }
        if canonicalLower == "triceps pushdown"
            || canonicalLower == "low cable triceps extension"
            || canonicalLower == "cable one arm tricep extension"
        {
            aliases.append(contentsOf: [
                "Cable Triceps Extension",
                "Cable Tricep Extension",
                "Cable Triceps Pushdown",
                "Triceps Extension (Cable)",
                "Tricep Pushdown (Cable)",
            ])
        }
        if canonicalLower == "dumbbell bicep curl" {
            aliases.append(contentsOf: [
                "Dumbbell Biceps Curl",
                "DB Bicep Curl",
                "Bicep Curl (Dumbbell)",
                "Curl (Dumbbell)",
            ])
        }
        if canonicalLower.contains("lat pulldown") {
            aliases.append(contentsOf: [
                "Lat Pulldown",
                "Lat Pulldown (Cable)",
                "Lat Pulldown (Wide Grip)",
                "Wide Grip Lat Pulldown",
                "Wide-Grip Lat Pulldown",
            ])
        }

        if hevyStyleTitle(canonicalName: canonicalName, equipment: equipment) != nil {
            let display = CatalogEquipmentMapper.hevyDisplayName(for: equipment)
            let prefixes = ["Barbell ", "Dumbbell ", "Cable ", "Machine ", "Kettlebell ", "Band ", "Smith Machine "]
            var stripped = canonicalName
            for prefix in prefixes where stripped.hasPrefix(prefix) {
                stripped = String(stripped.dropFirst(prefix.count))
                break
            }
            if !stripped.isEmpty {
                aliases.append("\(display) \(stripped)")
            }
        }

        return aliases
    }

    private static func pluralVariants(of name: String) -> [String] {
        if name.hasSuffix("s"), name.count > 3 {
            return [String(name.dropLast())]
        }
        return [name + "s"]
    }

    static func aliases(for record: FreeExerciseDBRecord, equipment: CatalogEquipment) -> [String] {
        var extraAliases: [String] = [record.name]
        if let hevyDisplay = hevyStyleTitle(canonicalName: record.name, equipment: equipment) {
            extraAliases.append(hevyDisplay)
            extraAliases.append(contentsOf: simplifiedHevyAliases(from: hevyDisplay))
        }
        extraAliases.append(contentsOf: pluralVariants(of: record.name))
        extraAliases.append(contentsOf: geminiStyleAliases(canonicalName: record.name, equipment: equipment))

        var seen = Set<String>()
        return extraAliases.compactMap { alias in
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let normalized = CatalogTitleNormalizer.normalize(trimmed)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return trimmed
        }
    }
}

enum ExerciseSeedCatalogMapper {
    static func mapRecord(_ record: FreeExerciseDBRecord) -> ExerciseSeedEntry {
        let equipment = CatalogEquipmentMapper.map(datasetEquipment: record.equipment, exerciseName: record.name)
        let muscles = CatalogMuscleMapper.muscles(
            primary: record.primaryMuscles,
            secondary: record.secondaryMuscles,
            exerciseName: record.name
        )
        let pattern = CatalogMovementPatternInferrer.infer(record: record)
        let mode = CatalogExerciseModeInferrer.infer(record: record, equipment: equipment, pattern: pattern)

        let hevyDisplay = CatalogAliasGenerator.hevyStyleTitle(canonicalName: record.name, equipment: equipment)
        let displayName = hevyDisplay ?? record.name
        let canonicalName = CatalogTitleNormalizer.normalize(record.name)
        let aliases = CatalogAliasGenerator.aliases(for: record, equipment: equipment)
        let hevyCanonicals = Set(HevyStyleExerciseCatalog.canonicalNames)
        let isHevyLibrary = hevyCanonicals.contains(canonicalName)
            || (hevyDisplay.map { hevyCanonicals.contains($0.lowercased()) } ?? false)

        return ExerciseSeedEntry(
            id: "seed-\(record.id)",
            canonicalName: canonicalName,
            displayName: displayName,
            aliases: aliases,
            exerciseMode: mode,
            equipment: CatalogEquipmentMapper.storageValue(for: equipment),
            primaryMuscleGroup: muscles.primary,
            secondaryMuscleGroups: muscles.secondaries,
            movementPattern: pattern.rawValue,
            sourceDatasetID: record.id,
            instructionText: FreeExerciseCatalogSupport.instructionText(for: record),
            imageURL: FreeExerciseCatalogSupport.imageURL(for: record),
            isPickerDefault: isHevyLibrary ? true : nil,
            isHevyLibrary: isHevyLibrary ? true : nil
        )
    }

    static func mapCatalogRecords(_ records: [FreeExerciseDBRecord]) -> [ExerciseSeedEntry] {
        records.map(mapRecord)
    }
}
