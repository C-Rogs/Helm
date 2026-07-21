public enum TrainingPhase: String, Sendable, Hashable, Codable, CaseIterable {
    case cut
    case maintain
    case gain
}

public struct PhaseGoal: Sendable, Hashable, Codable {
    public let phase: TrainingPhase
    /// Weekly body-mass change target for cut/gain phases (kg/week).
    public let weeklyRateKg: Double?
    public let targetMass: Mass?
    /// Free-form emphasis such as "v-taper" or "legs".
    public let emphasis: String?

    public init(
        phase: TrainingPhase,
        weeklyRateKg: Double? = nil,
        targetMass: Mass? = nil,
        emphasis: String? = nil
    ) {
        self.phase = phase
        self.weeklyRateKg = weeklyRateKg
        self.targetMass = targetMass
        self.emphasis = emphasis
    }
}
