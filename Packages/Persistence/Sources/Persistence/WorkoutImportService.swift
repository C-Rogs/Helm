import Core
import Foundation

public struct WorkoutImportResult: Sendable {
    public let session: WorkoutSessionDraft
    public let personalRecords: [DetectedPersonalRecord]

    public init(session: WorkoutSessionDraft, personalRecords: [DetectedPersonalRecord]) {
        self.session = session
        self.personalRecords = personalRecords
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

    public func importToHistory(
        parsed: ParsedWorkout,
        mappings: [String: String],
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        saveAliases: Bool = true
    ) throws -> WorkoutImportResult {
        let ended = endedAt ?? startedAt
        var sessionExercises: [WorkoutSessionExerciseDraft] = []

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
                SetEntryDraft(
                    id: set.id,
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
                    exerciseID: exerciseID,
                    displayOrder: index,
                    exerciseMode: summary.exerciseMode,
                    sets: sets
                )
            )
        }

        let draft = WorkoutSessionDraft(
            title: parsed.title,
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
