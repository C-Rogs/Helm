/// Phase within a single muscle's mesocycle block.
public enum MesocyclePhase: String, Sendable, Hashable, Codable {
    /// Ramping weekly hard-set targets from MEV toward MRV.
    case accumulating
    /// Scheduled volume reduction at the end of the block.
    case deload
}

/// Per-muscle mesocycle position and landmarks.
public struct MuscleMesocycleState: Sendable, Hashable, Codable {
    public var landmarks: VolumeLandmarks
    /// Total block length in weeks, including the deload week (4...6).
    public let blockLengthWeeks: Int
    /// Current week within the block, 1-based.
    public var currentWeek: Int

    public var phase: MesocyclePhase {
        currentWeek >= blockLengthWeeks ? .deload : .accumulating
    }

    public init(
        landmarks: VolumeLandmarks,
        blockLengthWeeks: Int,
        currentWeek: Int = 1
    ) {
        precondition((4 ... 6).contains(blockLengthWeeks), "block length must be 4...6 weeks")
        precondition((1 ... blockLengthWeeks).contains(currentWeek), "week must be within block")
        self.landmarks = landmarks
        self.blockLengthWeeks = blockLengthWeeks
        self.currentWeek = currentWeek
    }
}

/// Programme-wide mesocycle state keyed by muscle.
public struct MesocycleState: Sendable, Hashable, Codable {
    public var muscles: [MuscleGroup: MuscleMesocycleState]

    public init(muscles: [MuscleGroup: MuscleMesocycleState] = [:]) {
        self.muscles = muscles
    }
}
