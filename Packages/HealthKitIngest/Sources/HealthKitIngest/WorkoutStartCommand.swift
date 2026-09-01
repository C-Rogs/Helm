import CoachLLM
import Core
import Foundation
import Persistence

public struct WorkoutStartSetSpec: Codable, Sendable, Equatable {
    public let setType: String?
    public let reps: Int?
    public let massKg: Double?
    public let rpe: Double?

    public init(
        setType: String? = nil,
        reps: Int? = nil,
        massKg: Double? = nil,
        rpe: Double? = nil
    ) {
        self.setType = setType
        self.reps = reps
        self.massKg = massKg
        self.rpe = rpe
    }
}

public struct WorkoutStartExerciseSpec: Codable, Sendable, Equatable {
    public let name: String
    public let restSeconds: Int?
    public let sets: [WorkoutStartSetSpec]?

    public init(name: String, restSeconds: Int? = nil, sets: [WorkoutStartSetSpec]? = nil) {
        self.name = name
        self.restSeconds = restSeconds
        self.sets = sets
    }
}

public struct WorkoutStartPayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let helmDay: String?
    public let useAdjustedPrescription: Bool?
    public let title: String?
    public let exercises: [WorkoutStartExerciseSpec]?

    public init(
        schemaVersion: String,
        helmDay: String? = nil,
        useAdjustedPrescription: Bool? = nil,
        title: String? = nil,
        exercises: [WorkoutStartExerciseSpec]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.helmDay = helmDay
        self.useAdjustedPrescription = useAdjustedPrescription
        self.title = title
        self.exercises = exercises
    }

    public var exerciseLabels: [String] {
        exercises?.map(\.name) ?? []
    }

    public var hasDetailedSets: Bool {
        exercises?.contains { exercise in
            guard let sets = exercise.sets else { return false }
            return !sets.isEmpty
        } ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case helmDay
        case useAdjustedPrescription
        case title
        case exercises
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        helmDay = try container.decodeIfPresent(String.self, forKey: .helmDay)
        useAdjustedPrescription = try container.decodeIfPresent(Bool.self, forKey: .useAdjustedPrescription)
        title = try container.decodeIfPresent(String.self, forKey: .title)

        if let labels = try? container.decode([String].self, forKey: .exercises) {
            exercises = labels.map { WorkoutStartExerciseSpec(name: $0) }
        } else {
            exercises = try container.decodeIfPresent([WorkoutStartExerciseSpec].self, forKey: .exercises)
        }
    }
}

public enum WorkoutStartPayloadParser {
    public static func parse(from text: String) -> WorkoutStartPayload? {
        for schema in [CoachOutputSchemaVersion.workoutStartV2, .workoutStartV1] {
            guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: schema),
                  let data = block.data(using: .utf8),
                  let payload = try? JSONDecoder().decode(WorkoutStartPayload.self, from: data)
            else {
                continue
            }
            return payload
        }
        return nil
    }
}

public enum WorkoutStartSetTypeParser {
    public static func parse(_ raw: String?) -> SetType {
        guard let raw else { return .normal }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "warmup", "warm":
            return .warmup
        case "dropset", "drop":
            return .dropSet
        case "failure", "fail":
            return .failure
        case "assisted":
            return .assisted
        case "bodyweight", "bw":
            return .bodyweight
        case "timed", "time":
            return .timed
        case "distance":
            return .distance
        case "normal", "working", "work":
            return .normal
        default:
            return SetType(rawValue: raw) ?? .normal
        }
    }
}

public enum WorkoutStartPlanBuilder {
    public enum BuildError: LocalizedError, Equatable {
        case unresolvedExercise(String)

        public var errorDescription: String? {
            switch self {
            case let .unresolvedExercise(name):
                "Could not match exercise: \(name)"
            }
        }
    }

    public static func importedPlan(
        from payload: WorkoutStartPayload,
        persistence: PersistenceStore
    ) throws -> ImportedWorkoutPlan {
        guard let exercises = payload.exercises, !exercises.isEmpty else {
            throw BuildError.unresolvedExercise("session")
        }

        var plans: [ImportedWorkoutExercisePlan] = []
        for (index, exercise) in exercises.enumerated() {
            let label = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }
            guard let exerciseID = try resolveExerciseID(label: label, persistence: persistence) else {
                throw BuildError.unresolvedExercise(label)
            }
            guard let summary = try persistence.exercises.fetchSummary(id: exerciseID) else {
                throw BuildError.unresolvedExercise(label)
            }

            let sets = try resolvedSets(for: exercise, exerciseID: exerciseID, persistence: persistence)
            plans.append(
                ImportedWorkoutExercisePlan(
                    exerciseID: exerciseID,
                    displayOrder: index,
                    exerciseMode: summary.exerciseMode,
                    restDurationSeconds: exercise.restSeconds,
                    sets: sets
                )
            )
        }

        guard !plans.isEmpty else {
            throw BuildError.unresolvedExercise("session")
        }

        return ImportedWorkoutPlan(
            title: payload.title ?? "Today's session",
            exercises: plans
        )
    }

    private static func resolvedSets(
        for exercise: WorkoutStartExerciseSpec,
        exerciseID: String,
        persistence: PersistenceStore
    ) throws -> [ImportedWorkoutSetPlan] {
        if let sets = exercise.sets, !sets.isEmpty {
            return sets.enumerated().map { index, set in
                ImportedWorkoutSetPlan(
                    setIndex: index,
                    setType: WorkoutStartSetTypeParser.parse(set.setType),
                    mass: set.massKg.map { Mass(kilograms: $0) },
                    reps: set.reps,
                    rpe: set.rpe
                )
            }
        }

        return [
            ImportedWorkoutSetPlan(setIndex: 0, setType: .normal)
        ]
    }

    private static func resolveExerciseID(label: String, persistence: PersistenceStore) throws -> String? {
        let context = ExerciseResolver.Context(
            sessionExerciseIDs: [],
            mustBeInSession: false,
            phraseHint: label
        )
        if let resolved = ExerciseResolver.resolve(label, context: context, persistence: persistence).exerciseID {
            return resolved
        }

        if let resolved = try persistence.exercises.resolveImportedTitle(label)?.exerciseID {
            return resolved
        }

        let normalized = label.lowercased()
        if let resolved = try persistence.exercises.resolveExerciseID(normalizedAlias: normalized) {
            return resolved
        }

        let catalog = try persistence.exercises.fetchCatalogRows()
        if let match = catalog.first(where: { row in
            row.displayName.caseInsensitiveCompare(label) == .orderedSame
        }) {
            return match.id
        }

        let labelTokens = exerciseNameTokens(label)
        if !labelTokens.isEmpty,
           let match = catalog.first(where: { row in
               let tokens = exerciseNameTokens(row.displayName)
               return !tokens.isEmpty && (tokens.isSubset(of: labelTokens) || labelTokens.isSubset(of: tokens))
           }) {
            return match.id
        }

        return nil
    }

    private static func exerciseNameTokens(_ name: String) -> Set<String> {
        let folded = name.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return Set(String(folded).split(separator: " ").map(String.init).filter { $0.count > 1 })
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
                let template = byID[exerciseID] ?? base.exercises.first ?? PrescribedExercise(
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
