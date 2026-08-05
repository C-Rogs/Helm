import Core
import Foundation

public enum WorkoutImportMatchKind: String, Sendable, Codable {
    case alias
    case displayName
    case unresolved
    case manual
}

public struct WorkoutImportExerciseResolution: Sendable, Hashable, Identifiable {
    public let importedTitle: String
    public let exerciseID: String?
    public let matchKind: WorkoutImportMatchKind

    public var id: String { importedTitle }

    public init(importedTitle: String, exerciseID: String?, matchKind: WorkoutImportMatchKind) {
        self.importedTitle = importedTitle
        self.exerciseID = exerciseID
        self.matchKind = matchKind
    }

    public var isResolved: Bool { exerciseID != nil }
}

public struct WorkoutImportResolver: Sendable {
    private let exercises: ExerciseRepository

    public init(exercises: ExerciseRepository) {
        self.exercises = exercises
    }

    public func resolve(parsed: ParsedWorkout, manualMappings: [String: String] = [:]) throws -> [WorkoutImportExerciseResolution] {
        try resolve(titles: parsed.exercises.map(\.exerciseTitle), manualMappings: manualMappings)
    }

    public func resolve(
        titles: [String],
        manualMappings: [String: String] = [:]
    ) throws -> [WorkoutImportExerciseResolution] {
        var seen = Set<String>()
        var uniqueTitles: [String] = []
        for title in titles where seen.insert(title).inserted {
            uniqueTitles.append(title)
        }

        return try uniqueTitles.map { title in
            if let manualID = manualMappings[title] {
                return WorkoutImportExerciseResolution(
                    importedTitle: title,
                    exerciseID: manualID,
                    matchKind: .manual
                )
            }

            if let resolved = try exercises.resolveImportedTitle(title) {
                return WorkoutImportExerciseResolution(
                    importedTitle: title,
                    exerciseID: resolved.exerciseID,
                    matchKind: resolved.matchKind
                )
            }

            return WorkoutImportExerciseResolution(
                importedTitle: title,
                exerciseID: nil,
                matchKind: .unresolved
            )
        }
    }
}

public struct ResolvedImportedExerciseID: Sendable, Hashable {
    public let exerciseID: String
    public let matchKind: WorkoutImportMatchKind
}
