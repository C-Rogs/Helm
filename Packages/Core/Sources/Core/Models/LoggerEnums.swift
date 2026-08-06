import Foundation

public enum ExerciseMode: String, Codable, CaseIterable, Sendable {
    case weightReps = "weight_reps"
    case bodyweightReps = "bodyweight_reps"
    case duration = "duration"
    case distanceDuration = "distance_duration"
}

public enum WorkoutSessionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case completed
    case discarded
}

public enum WorkoutSessionSource: String, Codable, Sendable {
    case manual
    case template
    case prescription
    case importSource = "import"
}

public enum SetType: String, Codable, CaseIterable, Sendable {
    case warmup
    case normal
    case dropSet = "drop_set"
    case failure
    case assisted
    case bodyweight
    case timed
    case distance
    case restPauseActivation = "rest_pause_activation"
    case restPauseFollowUp = "rest_pause_follow_up"
}

public enum SetStatus: String, Codable, CaseIterable, Sendable {
    case planned
    case completed
    case skipped
}

public enum BlockType: String, Codable, Sendable {
    case superset
    case circuit
    case giantSet = "giant_set"
}

public enum PRMetricType: String, Codable, Sendable {
    case maxWeight = "max_weight"
    case bestEstimated1RM = "best_estimated_1rm"
    case bestSetVolume = "best_set_volume"
    case bestSessionVolume = "best_session_volume"
    case maxRepsAtWeight = "max_reps_at_weight"
}

public enum RestTimerPhase: String, Codable, CaseIterable, Sendable {
    case idle
    case running
    case paused
    case completed
    case skipped
}

public enum ActiveWorkoutRecoveryState: String, Codable, CaseIterable, Sendable {
    case active
    case stale
    case recoverable
}

public extension SetType {
    var isWarmup: Bool { self == .warmup }

    /// Counts toward prescribed `targetSets` (working slots). Drop sets are extras.
    var countsAsPrescribedWorkingSet: Bool {
        switch self {
        case .normal, .failure, .bodyweight, .restPauseActivation:
            return true
        case .warmup, .dropSet, .assisted, .timed, .distance, .restPauseFollowUp:
            return false
        }
    }

    /// Intensity-technique rows kept across prescription sync; not part of `targetSets`.
    var isPreservedIntensityTechnique: Bool {
        switch self {
        case .dropSet, .restPauseFollowUp:
            return true
        default:
            return false
        }
    }

    /// Set types cycled when tapping the set index during logging (Hevy-style).
    static let loggerCycle: [SetType] = [.normal, .warmup, .dropSet, .failure]

    func cycledForLogger() -> SetType {
        guard let index = Self.loggerCycle.firstIndex(of: self) else { return .normal }
        return Self.loggerCycle[(index + 1) % Self.loggerCycle.count]
    }

    /// Short label shown in the set-index column; nil for normal working sets.
    var loggerAbbreviation: String? {
        switch self {
        case .normal: nil
        case .warmup: "W"
        case .dropSet: "D"
        case .failure: "F"
        default: nil
        }
    }
}
