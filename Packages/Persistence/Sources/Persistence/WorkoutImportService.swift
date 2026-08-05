import Core
import Foundation

public struct ImportedWorkoutSetPlan: Sendable, Hashable {
    public let setIndex: Int
    public let setType: SetType
    public let mass: Mass?
    public let reps: Int?
    public let rpe: Double?

    public init(
        setIndex: Int,
        setType: SetType = .normal,
        mass: Mass? = nil,
        reps: Int? = nil,
        rpe: Double? = nil
    ) {
        self.setIndex = setIndex
        self.setType = setType
        self.mass = mass
        self.reps = reps
        self.rpe = rpe
    }
}

public struct ImportedWorkoutExercisePlan: Sendable, Hashable {
    public let exerciseID: String
    public let displayOrder: Int
    public let exerciseMode: ExerciseMode
    public let restDurationSeconds: Int?
    public let sets: [ImportedWorkoutSetPlan]

    public init(
        exerciseID: String,
        displayOrder: Int,
        exerciseMode: ExerciseMode,
        restDurationSeconds: Int? = nil,
        sets: [ImportedWorkoutSetPlan]
    ) {
        self.exerciseID = exerciseID
        self.displayOrder = displayOrder
        self.exerciseMode = exerciseMode
        self.restDurationSeconds = restDurationSeconds
        self.sets = sets
    }
}

public struct ImportedWorkoutPlan: Sendable, Hashable {
    public let title: String
    public let exercises: [ImportedWorkoutExercisePlan]
    public let contextNotes: String?

    public init(title: String, exercises: [ImportedWorkoutExercisePlan], contextNotes: String? = nil) {
        self.title = title
        self.exercises = exercises
        self.contextNotes = contextNotes
    }
}

public struct WorkoutImportResult: Sendable {
    public let session: WorkoutSessionDraft
    public let personalRecords: [DetectedPersonalRecord]

    public init(session: WorkoutSessionDraft, personalRecords: [DetectedPersonalRecord]) {
        self.session = session
        self.personalRecords = personalRecords
    }
}

public struct HevyBulkImportResult: Sendable, Hashable {
    public let importedSessionCount: Int
    public let skippedDuplicateCount: Int
    public let importedSetCount: Int

    public init(
        importedSessionCount: Int,
        skippedDuplicateCount: Int,
        importedSetCount: Int
    ) {
        self.importedSessionCount = importedSessionCount
        self.skippedDuplicateCount = skippedDuplicateCount
        self.importedSetCount = importedSetCount
    }
}

public struct WorkoutImportService: Sendable {
    private let sessions: WorkoutSessionRepository
    private let exercises: ExerciseRepository
    private let personalRecords: PersonalRecordRepository

    public init(
        sessions: WorkoutSessionRepository,
        exercises: ExerciseRepository,
        personalRecords: PersonalRecordRepository
    ) {
        self.sessions = sessions
        self.exercises = exercises
        self.personalRecords = personalRecords
    }

    public func buildPlan(
        parsed: ParsedWorkout,
        mappings: [String: String],
        saveAliases: Bool = true
    ) throws -> ImportedWorkoutPlan {
        var exercisePlans: [ImportedWorkoutExercisePlan] = []

        for (index, exercise) in parsed.exercises.enumerated() {
            guard let exerciseID = mappings[exercise.exerciseTitle] else {
                throw WorkoutImportServiceError.unresolvedExercise(exercise.exerciseTitle)
            }

            if saveAliases {
                try persistAliasIfNeeded(importedTitle: exercise.exerciseTitle, exerciseID: exerciseID)
            }

            guard let summary = try exercises.fetchSummary(id: exerciseID) else {
                throw WorkoutImportServiceError.missingExercise(exerciseID)
            }

            let sets = exercise.sets.enumerated().map { offset, set in
                ImportedWorkoutSetPlan(
                    setIndex: offset,
                    setType: set.setType,
                    mass: set.mass,
                    reps: set.reps,
                    rpe: set.rpe
                )
            }

            exercisePlans.append(
                ImportedWorkoutExercisePlan(
                    exerciseID: exerciseID,
                    displayOrder: index,
                    exerciseMode: summary.exerciseMode,
                    restDurationSeconds: exercise.restDurationSeconds,
                    sets: sets
                )
            )
        }

        return ImportedWorkoutPlan(
            title: parsed.title,
            exercises: exercisePlans,
            contextNotes: importContextNotes(from: parsed)
        )
    }

    private func importContextNotes(from parsed: ParsedWorkout) -> String? {
        var lines = parsed.skippedLines
        for exercise in parsed.exercises {
            for set in exercise.sets {
                if let note = set.prescriptionNote?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !note.isEmpty {
                    lines.append(note)
                }
            }
        }
        let unique = Array(Set(lines)).sorted()
        guard !unique.isEmpty else { return nil }
        return unique.joined(separator: "\n")
    }

    public func buildTemplate(
        parsed: ParsedWorkout,
        mappings: [String: String],
        saveAliases: Bool = true
    ) throws -> WorkoutTemplateDraft {
        let plan = try buildPlan(parsed: parsed, mappings: mappings, saveAliases: saveAliases)
        let templateExercises = plan.exercises.map { exercise in
            let reps = exercise.sets.compactMap(\.reps)
            return WorkoutTemplateExerciseDraft(
                exerciseID: exercise.exerciseID,
                displayOrder: exercise.displayOrder,
                targetSetCount: max(exercise.sets.count, 1),
                targetRepMin: reps.min(),
                targetRepMax: reps.max(),
                targetMass: exercise.sets.compactMap(\.mass).first,
                defaultRestSeconds: exercise.restDurationSeconds ?? 90
            )
        }

        return WorkoutTemplateDraft(
            name: plan.title,
            exercises: templateExercises
        )
    }

    /// Imports a pasted or parsed workout as a completed history session.
    public func importToHistory(
        parsed: ParsedWorkout,
        mappings: [String: String],
        sessionID: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        saveAliases: Bool = true,
        skipIfExists: Bool = false
    ) throws -> WorkoutImportResult? {
        if let sessionID, skipIfExists, try sessions.fetch(id: sessionID) != nil {
            return nil
        }

        let ended = endedAt ?? startedAt
        let plan = try buildPlan(parsed: parsed, mappings: mappings, saveAliases: saveAliases)
        var sessionExercises: [WorkoutSessionExerciseDraft] = []

        for exercise in plan.exercises {
            let sets = exercise.sets.enumerated().map { offset, set in
                SetEntryDraft(
                    setIndex: offset + 1,
                    setType: set.setType,
                    status: .completed,
                    mass: set.mass,
                    reps: set.reps,
                    rpe: set.rpe,
                    completedAt: startedAt
                )
            }

            sessionExercises.append(
                WorkoutSessionExerciseDraft(
                    exerciseID: exercise.exerciseID,
                    displayOrder: exercise.displayOrder,
                    exerciseMode: exercise.exerciseMode,
                    sets: sets
                )
            )
        }

        let draft = WorkoutSessionDraft(
            id: sessionID ?? UUID().uuidString,
            title: plan.title,
            startedAt: startedAt,
            endedAt: ended,
            status: .completed,
            source: .importSource,
            exercises: sessionExercises
        )

        try sessions.insert(draft)

        let detected = try PersonalRecordDetector.detect(in: draft, repository: sessions)
        for record in detected {
            try personalRecords.insert(
                PersonalRecord(
                    id: record.id,
                    exerciseID: record.exerciseID,
                    metricType: record.metricType,
                    metricValue: record.metricValue,
                    sourceSetEntryID: record.sourceSetEntryID,
                    sourceWorkoutSessionID: draft.id,
                    achievedAt: startedAt
                )
            )
        }

        return WorkoutImportResult(session: draft, personalRecords: detected)
    }

    /// Bulk-imports Hevy CSV sessions as completed history (skips existing session IDs).
    public func importHevySessions(
        _ sessionsToImport: [HevyCSVParsedSession],
        mappings: [String: String],
        saveAliases: Bool = true
    ) throws -> HevyBulkImportResult {
        if saveAliases {
            for (title, exerciseID) in mappings {
                try persistAliasIfNeeded(importedTitle: title, exerciseID: exerciseID)
            }
        }

        var importedSessions = 0
        var importedSets = 0
        var skippedDuplicates = 0

        for session in sessionsToImport {
            let result = try importToHistory(
                parsed: session.parsedWorkout,
                mappings: mappings,
                sessionID: session.id,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                saveAliases: false,
                skipIfExists: true
            )
            if let result {
                importedSessions += 1
                importedSets += result.session.exercises.reduce(0) { $0 + $1.sets.count }
            } else {
                skippedDuplicates += 1
            }
        }

        return HevyBulkImportResult(
            importedSessionCount: importedSessions,
            skippedDuplicateCount: skippedDuplicates,
            importedSetCount: importedSets
        )
    }

    private func persistAliasIfNeeded(importedTitle: String, exerciseID: String) throws {
        let normalized = importedTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }

        if let existing = try exercises.resolveExerciseID(normalizedAlias: normalized), existing == exerciseID {
            return
        }

        try exercises.addAlias(
            id: "alias-import-\(UUID().uuidString)",
            exerciseID: exerciseID,
            alias: importedTitle
        )
    }
}

public enum WorkoutImportServiceError: Error, Sendable, Equatable {
    case unresolvedExercise(String)
    case missingExercise(String)
}

extension WorkoutImportServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unresolvedExercise(title):
            "Map exercise before importing: \(title)"
        case let .missingExercise(id):
            "Exercise not found: \(id)"
        }
    }
}
