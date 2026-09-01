import Core
import Foundation

public enum ExercisePickerCuration: String, Codable, Sendable, Equatable {
    /// Only manifest overlay entries marked `isPickerDefault` appear in the default picker.
    case explicit
    /// Score ~220 staples from the full catalog (legacy loggy-style curation).
    case algorithmic
}

public struct ResolvedExerciseSeed: Sendable, Equatable {
    public let entries: [ExerciseSeedEntry]
    public let pickerCuration: ExercisePickerCuration
    public let explicitPickerIDs: Set<String>
    /// Overlay rows after catalog merge. `hiddenIDs` must not soft-delete these.
    public let overlayResolvedIDs: Set<String>

    public init(
        entries: [ExerciseSeedEntry],
        pickerCuration: ExercisePickerCuration,
        explicitPickerIDs: Set<String> = [],
        overlayResolvedIDs: Set<String> = []
    ) {
        self.entries = entries
        self.pickerCuration = pickerCuration
        self.explicitPickerIDs = explicitPickerIDs
        self.overlayResolvedIDs = overlayResolvedIDs
    }
}

public struct ExerciseSeedDocument: Codable, Sendable, Equatable {
    public let seedVersion: Int
    public let placeholder: Bool
    /// When set, exercises are loaded from a bundled free-exercise-db JSON array in the same directory.
    public let catalogResource: String?
    public let pickerCuration: ExercisePickerCuration?
    /// Catalogue exercise refs (overlay ids or `seed-<DatasetId>`) to soft-delete on import.
    /// Session history keeps its foreign keys; rows only disappear from picker/search.
    public let hiddenIDs: [String]?
    public let exercises: [ExerciseSeedEntry]

    public init(
        seedVersion: Int,
        placeholder: Bool,
        catalogResource: String? = nil,
        pickerCuration: ExercisePickerCuration? = nil,
        hiddenIDs: [String]? = nil,
        exercises: [ExerciseSeedEntry] = []
    ) {
        self.seedVersion = seedVersion
        self.placeholder = placeholder
        self.catalogResource = catalogResource
        self.pickerCuration = pickerCuration
        self.hiddenIDs = hiddenIDs
        self.exercises = exercises
    }
}

public struct ExerciseSeedEntry: Codable, Sendable, Equatable {
    public let id: String
    public let canonicalName: String
    public let displayName: String
    public let aliases: [String]
    public let exerciseMode: ExerciseMode
    public let equipment: String?
    public let primaryMuscleGroup: String?
    public let secondaryMuscleGroups: [String]
    public let movementPattern: String?
    public let sourceDatasetID: String?
    public let instructionText: String?
    public let coachingCues: [String]?
    public let imageURL: String?
    public let isPickerDefault: Bool?
    public let pickerRank: Int?
    public let isHevyLibrary: Bool?
    public let evidence: ExerciseSeedEvidence?

    enum CodingKeys: String, CodingKey {
        case id, canonicalName, displayName, aliases, exerciseMode, equipment
        case primaryMuscleGroup, secondaryMuscleGroups, movementPattern
        case sourceDatasetID, instructionText, coachingCues, imageURL
        case isPickerDefault, pickerRank, isHevyLibrary, evidence
    }

    public init(
        id: String,
        canonicalName: String,
        displayName: String,
        aliases: [String] = [],
        exerciseMode: ExerciseMode,
        equipment: String? = nil,
        primaryMuscleGroup: String? = nil,
        secondaryMuscleGroups: [String] = [],
        movementPattern: String? = nil,
        sourceDatasetID: String? = nil,
        instructionText: String? = nil,
        coachingCues: [String]? = nil,
        imageURL: String? = nil,
        isPickerDefault: Bool? = nil,
        pickerRank: Int? = nil,
        isHevyLibrary: Bool? = nil,
        evidence: ExerciseSeedEvidence? = nil
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.displayName = displayName
        self.aliases = aliases
        self.exerciseMode = exerciseMode
        self.equipment = equipment
        self.primaryMuscleGroup = primaryMuscleGroup
        self.secondaryMuscleGroups = secondaryMuscleGroups
        self.movementPattern = movementPattern
        self.sourceDatasetID = sourceDatasetID
        self.instructionText = instructionText
        self.coachingCues = coachingCues
        self.imageURL = imageURL
        self.isPickerDefault = isPickerDefault
        self.pickerRank = pickerRank
        self.isHevyLibrary = isHevyLibrary
        self.evidence = evidence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        canonicalName = try container.decode(String.self, forKey: .canonicalName)
        displayName = try container.decode(String.self, forKey: .displayName)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        exerciseMode = Self.decodeExerciseMode(container)
        equipment = try container.decodeIfPresent(String.self, forKey: .equipment)
        primaryMuscleGroup = try container.decodeIfPresent(String.self, forKey: .primaryMuscleGroup)
        secondaryMuscleGroups = try container.decodeIfPresent([String].self, forKey: .secondaryMuscleGroups) ?? []
        movementPattern = try container.decodeIfPresent(String.self, forKey: .movementPattern)
        sourceDatasetID = try container.decodeIfPresent(String.self, forKey: .sourceDatasetID)
        instructionText = try container.decodeIfPresent(String.self, forKey: .instructionText)
        coachingCues = try container.decodeIfPresent([String].self, forKey: .coachingCues)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        isPickerDefault = try container.decodeIfPresent(Bool.self, forKey: .isPickerDefault)
        pickerRank = try container.decodeIfPresent(Int.self, forKey: .pickerRank)
        isHevyLibrary = try container.decodeIfPresent(Bool.self, forKey: .isHevyLibrary)
        evidence = try container.decodeIfPresent(ExerciseSeedEvidence.self, forKey: .evidence)
    }

    private static func decodeExerciseMode(_ container: KeyedDecodingContainer<CodingKeys>) -> ExerciseMode {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: .exerciseMode) else {
            return .weightReps
        }
        if let mode = ExerciseMode(rawValue: raw) {
            return mode
        }
        switch raw {
        case "distanceDuration":
            return .distanceDuration
        case "weightReps":
            return .weightReps
        case "bodyweightReps":
            return .bodyweightReps
        default:
            return .weightReps
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(canonicalName, forKey: .canonicalName)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(aliases, forKey: .aliases)
        try container.encode(exerciseMode, forKey: .exerciseMode)
        try container.encodeIfPresent(equipment, forKey: .equipment)
        try container.encodeIfPresent(primaryMuscleGroup, forKey: .primaryMuscleGroup)
        try container.encode(secondaryMuscleGroups, forKey: .secondaryMuscleGroups)
        try container.encodeIfPresent(movementPattern, forKey: .movementPattern)
        try container.encodeIfPresent(sourceDatasetID, forKey: .sourceDatasetID)
        try container.encodeIfPresent(instructionText, forKey: .instructionText)
        try container.encodeIfPresent(coachingCues, forKey: .coachingCues)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encodeIfPresent(isPickerDefault, forKey: .isPickerDefault)
        try container.encodeIfPresent(pickerRank, forKey: .pickerRank)
        try container.encodeIfPresent(isHevyLibrary, forKey: .isHevyLibrary)
        try container.encodeIfPresent(evidence, forKey: .evidence)
    }
}

/// Per-exercise evidence ratings and citations from the seed library.
public struct ExerciseSeedEvidence: Codable, Sendable, Equatable {
    public let effectivenessRating: Double?
    public let stretchPositionBias: Double?
    public let stimulusToFatigue: Double?
    public let citationIDs: [String]

    public init(
        effectivenessRating: Double? = nil,
        stretchPositionBias: Double? = nil,
        stimulusToFatigue: Double? = nil,
        citationIDs: [String] = []
    ) {
        self.effectivenessRating = effectivenessRating
        self.stretchPositionBias = stretchPositionBias
        self.stimulusToFatigue = stimulusToFatigue
        self.citationIDs = citationIDs
    }
}

public struct ExerciseSeedImportResult: Sendable, Equatable {
    public let appliedSeedVersion: Int
    public let importedCount: Int
    public let skippedBecauseUpToDate: Bool

    public init(appliedSeedVersion: Int, importedCount: Int, skippedBecauseUpToDate: Bool) {
        self.appliedSeedVersion = appliedSeedVersion
        self.importedCount = importedCount
        self.skippedBecauseUpToDate = skippedBecauseUpToDate
    }
}
