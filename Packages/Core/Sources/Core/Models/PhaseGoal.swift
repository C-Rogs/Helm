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
    /// Free-form emphasis such as "v-taper" or "legs" (coach prose only).
    public let emphasis: String?
    /// Structured focus muscles as PlanKit `MuscleGroup.rawValue` strings, max 3.
    /// Engine redistributes weekly hard-set targets when non-empty. Not keyword-parsed from `emphasis`.
    public let musclePriorities: [String]

    public init(
        phase: TrainingPhase,
        weeklyRateKg: Double? = nil,
        targetMass: Mass? = nil,
        emphasis: String? = nil,
        musclePriorities: [String] = []
    ) {
        self.phase = phase
        self.weeklyRateKg = weeklyRateKg
        self.targetMass = targetMass
        self.emphasis = emphasis
        self.musclePriorities = Self.normalizedMusclePriorities(musclePriorities)
    }

    /// Cap 1…3 unique, lowercased, non-empty raw values (order preserved).
    public static func normalizedMusclePriorities(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            out.append(trimmed)
            if out.count == 3 { break }
        }
        return out
    }

    enum CodingKeys: String, CodingKey {
        case phase
        case weeklyRateKg
        case targetMass
        case emphasis
        case musclePriorities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phase = try container.decode(TrainingPhase.self, forKey: .phase)
        weeklyRateKg = try container.decodeIfPresent(Double.self, forKey: .weeklyRateKg)
        targetMass = try container.decodeIfPresent(Mass.self, forKey: .targetMass)
        emphasis = try container.decodeIfPresent(String.self, forKey: .emphasis)
        musclePriorities = Self.normalizedMusclePriorities(
            try container.decodeIfPresent([String].self, forKey: .musclePriorities) ?? []
        )
    }
}
