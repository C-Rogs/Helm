import CoachLLM
import Core
import Foundation
import Persistence

public struct WorkoutStartPayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let helmDay: String?
    public let useAdjustedPrescription: Bool?
    public let exercises: [String]?

    public init(
        schemaVersion: String,
        helmDay: String? = nil,
        useAdjustedPrescription: Bool? = nil,
        exercises: [String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.helmDay = helmDay
        self.useAdjustedPrescription = useAdjustedPrescription
        self.exercises = exercises
    }
}

public enum WorkoutStartPayloadParser {
    public static func parse(from text: String) -> WorkoutStartPayload? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            return nil
        }
        let snippet = String(text[start ... end])
        guard let data = snippet.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkoutStartPayload.self, from: data)
    }
}

public enum WorkoutStartPrescriptionResolver {
    public static func prescription(
        exerciseLabels: [String],
        base: SessionPrescription,
        persistence: PersistenceStore
    ) throws -> SessionPrescription? {
        let trimmedLabels = exerciseLabels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedLabels.isEmpty else { return nil }

        var resolved: [PrescribedExercise] = []
        var unresolved: [String] = []
        let byID = Dictionary(uniqueKeysWithValues: base.exercises.map { ($0.exerciseID, $0) })
        let displayNames = try persistence.exercises.displayNames(for: base.exercises.map(\.exerciseID))

        for (index, label) in trimmedLabels.enumerated() {
            if let exercise = byID[label] {
                resolved.append(
                    PrescribedExercise(
                        id: exercise.id,
                        exerciseID: exercise.exerciseID,
                        order: index,
                        targetSets: exercise.targetSets,
                        targetRepMin: exercise.targetRepMin,
                        targetRepMax: exercise.targetRepMax,
                        targetMass: exercise.targetMass,
                        targetRPE: exercise.targetRPE,
                        rationale: exercise.rationale,
                        evidenceIDs: exercise.evidenceIDs
                    )
                )
                continue
            }

            if let exerciseID = try persistence.exercises.resolveImportedTitle(label)?.exerciseID {
                let template = base.exercises.first ?? PrescribedExercise(
                    exerciseID: exerciseID,
                    order: index,
                    targetSets: 3,
                    targetRepMin: 8,
                    targetRepMax: 12
                )
                resolved.append(
                    PrescribedExercise(
                        exerciseID: exerciseID,
                        order: index,
                        targetSets: template.targetSets,
                        targetRepMin: template.targetRepMin,
                        targetRepMax: template.targetRepMax,
                        targetMass: template.targetMass,
                        targetRPE: template.targetRPE,
                        rationale: template.rationale,
                        evidenceIDs: template.evidenceIDs
                    )
                )
                continue
            }

            if let match = displayNames.first(where: { $0.value.caseInsensitiveCompare(label) == .orderedSame }) {
                let exercise = byID[match.key]!
                resolved.append(
                    PrescribedExercise(
                        id: exercise.id,
                        exerciseID: exercise.exerciseID,
                        order: index,
                        targetSets: exercise.targetSets,
                        targetRepMin: exercise.targetRepMin,
                        targetRepMax: exercise.targetRepMax,
                        targetMass: exercise.targetMass,
                        targetRPE: exercise.targetRPE,
                        rationale: exercise.rationale,
                        evidenceIDs: exercise.evidenceIDs
                    )
                )
                continue
            }

            unresolved.append(label)
        }

        guard unresolved.isEmpty else { return nil }

        let baseOrder = base.exercises.map(\.exerciseID)
        let resolvedOrder = resolved.map(\.exerciseID)
        guard resolvedOrder != baseOrder else { return nil }

        return SessionPrescription(
            id: base.id,
            helmDay: base.helmDay,
            title: base.title,
            exercises: resolved
        )
    }
}
