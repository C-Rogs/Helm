import Core
import Foundation

public struct TrainingHistoryExport: Codable, Sendable, Hashable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let exportedAt: Date
    public let lookbackDays: Int
    public let sessions: [TrainingHistorySession]
    public let customExercises: [TrainingHistoryCustomExercise]
    public let aliases: [TrainingHistoryAlias]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        exportedAt: Date = Date(),
        lookbackDays: Int,
        sessions: [TrainingHistorySession],
        customExercises: [TrainingHistoryCustomExercise],
        aliases: [TrainingHistoryAlias]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.lookbackDays = lookbackDays
        self.sessions = sessions
        self.customExercises = customExercises
        self.aliases = aliases
    }
}

public struct TrainingHistoryCustomExercise: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let exerciseMode: ExerciseMode
    public let primaryMuscleGroup: String?

    public init(
        id: String,
        displayName: String,
        exerciseMode: ExerciseMode,
        primaryMuscleGroup: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.exerciseMode = exerciseMode
        self.primaryMuscleGroup = primaryMuscleGroup
    }
}

public struct TrainingHistoryAlias: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let exerciseID: String
    public let alias: String

    public init(id: String, exerciseID: String, alias: String) {
        self.id = id
        self.exerciseID = exerciseID
        self.alias = alias
    }
}

public struct TrainingHistorySession: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String?
    public let notes: String?
    public let startedAt: Date
    public let endedAt: Date?
    public let source: WorkoutSessionSource
    public let exercises: [TrainingHistoryExercise]

    public init(
        id: String,
        title: String?,
        notes: String? = nil,
        startedAt: Date,
        endedAt: Date?,
        source: WorkoutSessionSource,
        exercises: [TrainingHistoryExercise]
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.source = source
        self.exercises = exercises
    }
}

public struct TrainingHistoryExercise: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let exerciseID: String
    public let displayOrder: Int
    public let exerciseMode: ExerciseMode
    public let sets: [TrainingHistorySet]

    public init(
        id: String,
        exerciseID: String,
        displayOrder: Int,
        exerciseMode: ExerciseMode,
        sets: [TrainingHistorySet]
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.displayOrder = displayOrder
        self.exerciseMode = exerciseMode
        self.sets = sets
    }
}

public struct TrainingHistorySet: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let setIndex: Int
    public let setType: SetType
    public let massKilograms: Double?
    public let reps: Int?
    public let rpe: Double?
    public let rir: Double?
    public let completedAt: Date?

    public init(
        id: String,
        setIndex: Int,
        setType: SetType,
        massKilograms: Double?,
        reps: Int?,
        rpe: Double?,
        rir: Double?,
        completedAt: Date?
    ) {
        self.id = id
        self.setIndex = setIndex
        self.setType = setType
        self.massKilograms = massKilograms
        self.reps = reps
        self.rpe = rpe
        self.rir = rir
        self.completedAt = completedAt
    }
}

public struct TrainingHistoryImportResult: Sendable, Hashable {
    public let importedSessionCount: Int
    public let skippedDuplicateCount: Int
    public let importedSetCount: Int
    public let upsertedCustomExerciseCount: Int
    public let upsertedAliasCount: Int

    public init(
        importedSessionCount: Int,
        skippedDuplicateCount: Int,
        importedSetCount: Int,
        upsertedCustomExerciseCount: Int,
        upsertedAliasCount: Int
    ) {
        self.importedSessionCount = importedSessionCount
        self.skippedDuplicateCount = skippedDuplicateCount
        self.importedSetCount = importedSetCount
        self.upsertedCustomExerciseCount = upsertedCustomExerciseCount
        self.upsertedAliasCount = upsertedAliasCount
    }
}

public enum TrainingHistoryExportError: Error, Sendable, Equatable {
    case unsupportedSchemaVersion(Int)
    case decodingFailed
}

extension TrainingHistoryExportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchemaVersion(version):
            "Unsupported training history schema version: \(version)"
        case .decodingFailed:
            "Could not decode training history JSON."
        }
    }
}

public struct TrainingHistoryExportService: Sendable {
    public static let defaultLookbackDays = 90

    private let sessions: WorkoutSessionRepository
    private let exercises: ExerciseRepository

    public init(sessions: WorkoutSessionRepository, exercises: ExerciseRepository) {
        self.sessions = sessions
        self.exercises = exercises
    }

    public func exportHistory(
        lookbackDays: Int = defaultLookbackDays,
        now: Date = Date()
    ) throws -> TrainingHistoryExport {
        let since = now.addingTimeInterval(-Double(lookbackDays) * 86_400)
        let drafts = try sessions.fetchCompletedSessions(since: since)

        let historySessions = drafts.map { draft -> TrainingHistorySession in
            TrainingHistorySession(
                id: draft.id,
                title: draft.title,
                notes: draft.notes,
                startedAt: draft.startedAt,
                endedAt: draft.endedAt,
                source: draft.source,
                exercises: draft.exercises.map { exercise in
                    TrainingHistoryExercise(
                        id: exercise.id,
                        exerciseID: exercise.exerciseID,
                        displayOrder: exercise.displayOrder,
                        exerciseMode: exercise.exerciseMode,
                        sets: exercise.sets.map { set in
                            TrainingHistorySet(
                                id: set.id,
                                setIndex: set.setIndex,
                                setType: set.setType,
                                massKilograms: set.mass?.kilograms,
                                reps: set.reps,
                                rpe: set.rpe,
                                rir: set.rir,
                                completedAt: set.completedAt
                            )
                        }
                    )
                }
            )
        }

        let usedExerciseIDs = Set(drafts.flatMap { $0.exercises.map(\.exerciseID) })
        let custom = try exercises.fetchCustomExercises()
            .filter { usedExerciseIDs.contains($0.id) }
            .map {
                TrainingHistoryCustomExercise(
                    id: $0.id,
                    displayName: $0.displayName,
                    exerciseMode: $0.exerciseMode,
                    primaryMuscleGroup: $0.primaryMuscleGroup
                )
            }
        let aliases = try exercises.fetchAliases(forExerciseIDs: usedExerciseIDs)
            .map {
                TrainingHistoryAlias(id: $0.id, exerciseID: $0.exerciseID, alias: $0.alias)
            }

        return TrainingHistoryExport(
            exportedAt: now,
            lookbackDays: lookbackDays,
            sessions: historySessions,
            customExercises: custom,
            aliases: aliases
        )
    }

    public func encode(_ export: TrainingHistoryExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    public func decode(_ data: Data) throws -> TrainingHistoryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let export = try decoder.decode(TrainingHistoryExport.self, from: data)
            guard export.schemaVersion <= TrainingHistoryExport.currentSchemaVersion else {
                throw TrainingHistoryExportError.unsupportedSchemaVersion(export.schemaVersion)
            }
            return export
        } catch let error as TrainingHistoryExportError {
            throw error
        } catch {
            throw TrainingHistoryExportError.decodingFailed
        }
    }

    public func importHistory(_ export: TrainingHistoryExport) throws -> TrainingHistoryImportResult {
guard export.schemaVersion <= TrainingHistoryExport.currentSchemaVersion else {
                throw TrainingHistoryExportError.unsupportedSchemaVersion(export.schemaVersion)
            }

        var upsertedCustom = 0
        for custom in export.customExercises {
            try exercises.upsert(
                id: custom.id,
                canonicalName: custom.displayName.lowercased(),
                displayName: custom.displayName,
                exerciseMode: custom.exerciseMode,
                isCustom: true,
                primaryMuscleGroup: custom.primaryMuscleGroup
            )
            upsertedCustom += 1
        }

        var upsertedAliases = 0
        for alias in export.aliases {
            let normalized = alias.alias.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let existing = try exercises.resolveExerciseID(normalizedAlias: normalized),
               existing == alias.exerciseID {
                continue
            }
            try exercises.addAlias(id: alias.id, exerciseID: alias.exerciseID, alias: alias.alias)
            upsertedAliases += 1
        }

        var importedSessions = 0
        var skipped = 0
        var importedSets = 0

        for session in export.sessions {
            if try sessions.fetch(id: session.id) != nil {
                skipped += 1
                continue
            }

            let draft = WorkoutSessionDraft(
                id: session.id,
                title: session.title,
                notes: session.notes,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                status: .completed,
                source: session.source,
                exercises: session.exercises.map { exercise in
                    WorkoutSessionExerciseDraft(
                        id: exercise.id,
                        exerciseID: exercise.exerciseID,
                        displayOrder: exercise.displayOrder,
                        exerciseMode: exercise.exerciseMode,
                        sets: exercise.sets.map { set in
                            SetEntryDraft(
                                id: set.id,
                                setIndex: set.setIndex,
                                setType: set.setType,
                                status: .completed,
                                mass: set.massKilograms.map { Mass(kilograms: $0) },
                                reps: set.reps,
                                rpe: set.rpe,
                                rir: set.rir,
                                completedAt: set.completedAt ?? session.startedAt
                            )
                        }
                    )
                }
            )

            try sessions.insert(draft)
            importedSessions += 1
            importedSets += draft.exercises.reduce(0) { $0 + $1.sets.count }
        }

        return TrainingHistoryImportResult(
            importedSessionCount: importedSessions,
            skippedDuplicateCount: skipped,
            importedSetCount: importedSets,
            upsertedCustomExerciseCount: upsertedCustom,
            upsertedAliasCount: upsertedAliases
        )
    }

    public func writeExportFile(
        lookbackDays: Int = defaultLookbackDays,
        now: Date = Date()
    ) throws -> URL {
        let export = try exportHistory(lookbackDays: lookbackDays, now: now)
        let data = try encode(export)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-training-history-\(stamp).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}
