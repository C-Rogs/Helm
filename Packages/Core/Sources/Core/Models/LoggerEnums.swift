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
}
