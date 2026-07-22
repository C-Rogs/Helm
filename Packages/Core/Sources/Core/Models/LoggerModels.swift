import Foundation

public struct ExerciseSummary: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let displayName: String
    public let exerciseMode: ExerciseMode
    public let isCustom: Bool
    public let primaryMuscleGroup: String?

    public init(
        id: String,
        displayName: String,
        exerciseMode: ExerciseMode,
        isCustom: Bool,
        primaryMuscleGroup: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.exerciseMode = exerciseMode
        self.isCustom = isCustom
        self.primaryMuscleGroup = primaryMuscleGroup
    }
}

public struct ExerciseAlias: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let exerciseID: String
    public let alias: String
    public let normalizedAlias: String

    public init(id: String, exerciseID: String, alias: String, normalizedAlias: String) {
        self.id = id
        self.exerciseID = exerciseID
        self.alias = alias
        self.normalizedAlias = normalizedAlias
    }
}

public struct PreviousPerformance: Sendable, Hashable, Codable {
    public let exerciseID: String
    public let setIndex: Int
    public let setType: SetType
    public let mass: Mass?
    public let reps: Int?
    public let distanceKilometers: Double?
    public let durationSeconds: Int?
    public let completedAt: Date

    public init(
        exerciseID: String,
        setIndex: Int,
        setType: SetType,
        mass: Mass? = nil,
        reps: Int? = nil,
        distanceKilometers: Double? = nil,
        durationSeconds: Int? = nil,
        completedAt: Date
    ) {
        self.exerciseID = exerciseID
        self.setIndex = setIndex
        self.setType = setType
        self.mass = mass
        self.reps = reps
        self.distanceKilometers = distanceKilometers
        self.durationSeconds = durationSeconds
        self.completedAt = completedAt
    }
}

public struct SetEntryDraft: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let setIndex: Int
    public let setType: SetType
    public let status: SetStatus
    public let mass: Mass?
    public let reps: Int?
    public let distanceKilometers: Double?
    public let durationSeconds: Int?
    public let rpe: Double?
    public let rir: Double?
    public let completedAt: Date?

    public init(
        id: String = UUID().uuidString,
        setIndex: Int,
        setType: SetType = .normal,
        status: SetStatus = .completed,
        mass: Mass? = nil,
        reps: Int? = nil,
        distanceKilometers: Double? = nil,
        durationSeconds: Int? = nil,
        rpe: Double? = nil,
        rir: Double? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.setIndex = setIndex
        self.setType = setType
        self.status = status
        self.mass = mass
        self.reps = reps
        self.distanceKilometers = distanceKilometers
        self.durationSeconds = durationSeconds
        self.rpe = rpe
        self.rir = rir
        self.completedAt = completedAt
    }
}

public struct WorkoutSessionExerciseDraft: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let exerciseID: String
    public let displayOrder: Int
    public let exerciseMode: ExerciseMode
    public let sets: [SetEntryDraft]

    public init(
        id: String = UUID().uuidString,
        exerciseID: String,
        displayOrder: Int,
        exerciseMode: ExerciseMode,
        sets: [SetEntryDraft]
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.displayOrder = displayOrder
        self.exerciseMode = exerciseMode
        self.sets = sets
    }
}

public struct WorkoutSessionDraft: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let title: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let status: WorkoutSessionStatus
    public let source: WorkoutSessionSource
    public let exercises: [WorkoutSessionExerciseDraft]

    public init(
        id: String = UUID().uuidString,
        title: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        status: WorkoutSessionStatus = .completed,
        source: WorkoutSessionSource = .manual,
        exercises: [WorkoutSessionExerciseDraft]
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.source = source
        self.exercises = exercises
    }
}

public struct WorkoutTemplateSummary: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let notes: String?

    public init(id: String, name: String, notes: String? = nil) {
        self.id = id
        self.name = name
        self.notes = notes
    }
}

public struct WorkoutTemplateExerciseDraft: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let exerciseID: String
    public let displayOrder: Int
    public let targetSetCount: Int?
    public let targetRepMin: Int?
    public let targetRepMax: Int?
    public let targetMass: Mass?
    public let defaultRestSeconds: Int?

    public init(
        id: String = UUID().uuidString,
        exerciseID: String,
        displayOrder: Int,
        targetSetCount: Int? = nil,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        targetMass: Mass? = nil,
        defaultRestSeconds: Int? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.displayOrder = displayOrder
        self.targetSetCount = targetSetCount
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.targetMass = targetMass
        self.defaultRestSeconds = defaultRestSeconds
    }
}

public struct WorkoutTemplateDraft: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let notes: String?
    public let exercises: [WorkoutTemplateExerciseDraft]

    public init(
        id: String = UUID().uuidString,
        name: String,
        notes: String? = nil,
        exercises: [WorkoutTemplateExerciseDraft]
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.exercises = exercises
    }
}

public struct WorkoutSessionSummary: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let title: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let totalVolumeKilograms: Double
    public let totalSetCount: Int
    public let totalRepCount: Int
    public let exerciseCount: Int

    public init(
        id: String,
        title: String? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        totalVolumeKilograms: Double,
        totalSetCount: Int,
        totalRepCount: Int,
        exerciseCount: Int
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totalVolumeKilograms = totalVolumeKilograms
        self.totalSetCount = totalSetCount
        self.totalRepCount = totalRepCount
        self.exerciseCount = exerciseCount
    }
}

public struct DetectedPersonalRecord: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let exerciseID: String
    public let metricType: PRMetricType
    public let metricValue: Double
    public let sourceSetEntryID: String?
    public let previousBest: Double?

    public init(
        id: String = UUID().uuidString,
        exerciseID: String,
        metricType: PRMetricType,
        metricValue: Double,
        sourceSetEntryID: String? = nil,
        previousBest: Double? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.metricType = metricType
        self.metricValue = metricValue
        self.sourceSetEntryID = sourceSetEntryID
        self.previousBest = previousBest
    }
}

public struct PersonalRecord: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let exerciseID: String
    public let metricType: PRMetricType
    public let metricValue: Double
    public let sourceSetEntryID: String?
    public let sourceWorkoutSessionID: String?
    public let achievedAt: Date

    public init(
        id: String = UUID().uuidString,
        exerciseID: String,
        metricType: PRMetricType,
        metricValue: Double,
        sourceSetEntryID: String? = nil,
        sourceWorkoutSessionID: String? = nil,
        achievedAt: Date
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.metricType = metricType
        self.metricValue = metricValue
        self.sourceSetEntryID = sourceSetEntryID
        self.sourceWorkoutSessionID = sourceWorkoutSessionID
        self.achievedAt = achievedAt
    }
}
