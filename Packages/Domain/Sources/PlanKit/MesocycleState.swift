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
    /// Reactive deload proposed by the engine; requires user confirm before deload week applies.
    public var pendingReactiveDeload: Bool
    /// Consecutive training days logged in the depleted readiness band.
    public var consecutiveDepletedDays: Int

    public init(
        muscles: [MuscleGroup: MuscleMesocycleState] = [:],
        pendingReactiveDeload: Bool = false,
        consecutiveDepletedDays: Int = 0
    ) {
        self.muscles = muscles
        self.pendingReactiveDeload = pendingReactiveDeload
        self.consecutiveDepletedDays = consecutiveDepletedDays
    }

    enum CodingKeys: String, CodingKey {
        case muscles
        case pendingReactiveDeload
        case consecutiveDepletedDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        muscles = try container.decode([MuscleGroup: MuscleMesocycleState].self, forKey: .muscles)
        pendingReactiveDeload = try container.decodeIfPresent(Bool.self, forKey: .pendingReactiveDeload) ?? false
        consecutiveDepletedDays = try container.decodeIfPresent(Int.self, forKey: .consecutiveDepletedDays) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(muscles, forKey: .muscles)
        try container.encode(pendingReactiveDeload, forKey: .pendingReactiveDeload)
        try container.encode(consecutiveDepletedDays, forKey: .consecutiveDepletedDays)
    }
}
