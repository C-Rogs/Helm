import Core
import Foundation

/// Per-lift progression targets derived from logged history.
public struct LiftProgression: Sendable, Hashable, Codable {
    public let exerciseID: String
    public let estimatedOneRepMax: Mass?
    public let workingWeight: Mass?
    public let targetRepMin: Int
    public let targetRepMax: Int

    public init(
        exerciseID: String,
        estimatedOneRepMax: Mass? = nil,
        workingWeight: Mass? = nil,
        targetRepMin: Int = 8,
        targetRepMax: Int = 12
    ) {
        self.exerciseID = exerciseID
        self.estimatedOneRepMax = estimatedOneRepMax
        self.workingWeight = workingWeight
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
    }
}

/// Compound vs isolation progression style.
enum LiftKind: Sendable, Hashable {
    case compound
    case isolation

    var repRange: (min: Int, max: Int) {
        switch self {
        case .compound: (8, 12)
        case .isolation: (10, 15)
        }
    }

    var weightBumpFraction: Double {
        switch self {
        case .compound: 0.025
        case .isolation: 0.0125
        }
    }
}

enum ProgressionEngine {
    static let defaultRepMin = 8
    static let defaultRepMax = 12

    static func liftKind(exerciseID: String, muscleMap: ExerciseMuscleMap?) -> LiftKind {
        let id = exerciseID.lowercased()
        let isolationKeywords = [
            "curl", "extension", "fly", "flye", "raise", "kickback",
            "pullover", "pushdown", "crunch", "calf"
        ]
        let compoundKeywords = [
            "press", "squat", "deadlift", "row", "pullup", "pull-up", "lunge", "rdl"
        ]
        if isolationKeywords.contains(where: { id.contains($0) }) {
            return .isolation
        }
        if compoundKeywords.contains(where: { id.contains($0) }) {
            return .compound
        }
        if let muscleMap, muscleMap.contributions.count == 1,
           muscleMap.contributions[0].isDirect {
            return .isolation
        }
        return .compound
    }

    /// Epley estimated 1RM from a single logged set.
    static func estimatedOneRepMax(mass: Mass, reps: Int) -> Mass {
        let e1rmKg = mass.kilograms * (1.0 + Double(reps) / 30.0)
        return Mass(kilograms: e1rmKg)
    }

    static func bestEstimatedOneRepMax(from sets: [LoggedSet]) -> Mass? {
        let working = sets.filter { !$0.isWarmup && $0.mass != nil && $0.reps != nil }
        guard !working.isEmpty else { return nil }
        return working.map { set in
            estimatedOneRepMax(mass: set.mass!, reps: set.reps!)
        }.max(by: { $0.kilograms < $1.kilograms })
    }

    static func progression(
        for exerciseID: String,
        history: [LoggedSet],
        muscleMap: ExerciseMuscleMap? = nil
    ) -> LiftProgression {
        let kind = liftKind(exerciseID: exerciseID, muscleMap: muscleMap)
        let repMin = kind.repRange.min
        let repMax = kind.repRange.max

        let exerciseSets = history
            .filter { $0.exerciseID == exerciseID }
            .sorted { $0.completedAt < $1.completedAt }

        let e1rm = bestEstimatedOneRepMax(from: exerciseSets)
        let workingSets = exerciseSets.filter { !$0.isWarmup && $0.mass != nil && $0.reps != nil }

        guard let latest = workingSets.last else {
            return LiftProgression(
                exerciseID: exerciseID,
                estimatedOneRepMax: e1rm,
                workingWeight: nil,
                targetRepMin: repMin,
                targetRepMax: repMax
            )
        }

        let currentWeight = latest.mass!

        let latestSessionSets = workingSets.filter {
            abs($0.completedAt.timeIntervalSince(latest.completedAt)) < 1
        }

        let hitTopOfRange = latestSessionSets.allSatisfy { set in
            guard let reps = set.reps else { return false }
            return reps >= repMax
        }
        let recoveredEnough = latestSessionSets.allSatisfy { set in
            guard let rir = set.rir else { return true }
            return rir >= 1
        }

        let nextWeight: Mass
        if hitTopOfRange && recoveredEnough {
            nextWeight = Mass(kilograms: currentWeight.kilograms * (1.0 + kind.weightBumpFraction))
        } else {
            nextWeight = currentWeight
        }

        return LiftProgression(
            exerciseID: exerciseID,
            estimatedOneRepMax: e1rm,
            workingWeight: nextWeight,
            targetRepMin: repMin,
            targetRepMax: repMax
        )
    }
}
