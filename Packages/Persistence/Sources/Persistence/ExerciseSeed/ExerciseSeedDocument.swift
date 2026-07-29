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

    public init(
        entries: [ExerciseSeedEntry],
        pickerCuration: ExercisePickerCuration,
        explicitPickerIDs: Set<String> = []
    ) {
        self.entries = entries
        self.pickerCuration = pickerCuration
        self.explicitPickerIDs = explicitPickerIDs
    }
}

public struct ExerciseSeedDocument: Codable, Sendable, Equatable {
    public let seedVersion: Int
    public let placeholder: Bool
    /// When set, exercises are loaded from a bundled free-exercise-db JSON array in the same directory.
    public let catalogResource: String?
    public let pickerCuration: ExercisePickerCuration?
    public let exercises: [ExerciseSeedEntry]

    public init(
        seedVersion: Int,
        placeholder: Bool,
        catalogResource: String? = nil,
        pickerCuration: ExercisePickerCuration? = nil,
        exercises: [ExerciseSeedEntry] = []
    ) {
        self.seedVersion = seedVersion
        self.placeholder = placeholder
        self.catalogResource = catalogResource
        self.pickerCuration = pickerCuration
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
    public let isHevyLibrary: Bool?
    public let evidence: ExerciseSeedEvidence?

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
        self.isHevyLibrary = isHevyLibrary
        self.evidence = evidence
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
