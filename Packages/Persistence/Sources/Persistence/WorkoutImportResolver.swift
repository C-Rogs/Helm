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
        try parsed.exercises.map { exercise in
            if let manualID = manualMappings[exercise.exerciseTitle] {
                return WorkoutImportExerciseResolution(
                    importedTitle: exercise.exerciseTitle,
                    exerciseID: manualID,
                    matchKind: .manual
                )
            }

            if let resolved = try exercises.resolveImportedTitle(exercise.exerciseTitle) {
                return WorkoutImportExerciseResolution(
                    importedTitle: exercise.exerciseTitle,
                    exerciseID: resolved.exerciseID,
                    matchKind: resolved.matchKind
                )
            }

            return WorkoutImportExerciseResolution(
                importedTitle: exercise.exerciseTitle,
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
