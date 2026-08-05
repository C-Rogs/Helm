import Foundation

public struct LoggedSet: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let exerciseID: String
    public let sequence: Int
    public let mass: Mass?
    public let reps: Int?
    public let rir: Int?
    public let rpe: Double?
    public let completedAt: Date
    public let setType: SetType

    public var isWarmup: Bool { setType.isWarmup }

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        sequence: Int,
        mass: Mass? = nil,
        reps: Int? = nil,
        rir: Int? = nil,
        rpe: Double? = nil,
        completedAt: Date,
        setType: SetType = .normal
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.sequence = sequence
        self.mass = mass
        self.reps = reps
        self.rir = rir
        self.rpe = rpe
        self.completedAt = completedAt
        self.setType = setType
    }

    /// Compatibility initializer for call sites that still pass `isWarmup`.
    public init(
        id: UUID = UUID(),
        exerciseID: String,
        sequence: Int,
        mass: Mass? = nil,
        reps: Int? = nil,
        rir: Int? = nil,
        rpe: Double? = nil,
        completedAt: Date,
        isWarmup: Bool
    ) {
        self.init(
            id: id,
            exerciseID: exerciseID,
            sequence: sequence,
            mass: mass,
            reps: reps,
            rir: rir,
            rpe: rpe,
            completedAt: completedAt,
            setType: isWarmup ? .warmup : .normal
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        exerciseID = try container.decode(String.self, forKey: .exerciseID)
        sequence = try container.decode(Int.self, forKey: .sequence)
        mass = try container.decodeIfPresent(Mass.self, forKey: .mass)
        reps = try container.decodeIfPresent(Int.self, forKey: .reps)
        rir = try container.decodeIfPresent(Int.self, forKey: .rir)
        rpe = try container.decodeIfPresent(Double.self, forKey: .rpe)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        if let decoded = try container.decodeIfPresent(SetType.self, forKey: .setType) {
            setType = decoded
        } else if let warmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) {
            setType = warmup ? .warmup : .normal
        } else {
            setType = .normal
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encode(sequence, forKey: .sequence)
        try container.encodeIfPresent(mass, forKey: .mass)
        try container.encodeIfPresent(reps, forKey: .reps)
        try container.encodeIfPresent(rir, forKey: .rir)
        try container.encodeIfPresent(rpe, forKey: .rpe)
        try container.encode(completedAt, forKey: .completedAt)
        try container.encode(setType, forKey: .setType)
        try container.encode(isWarmup, forKey: .isWarmup)
    }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseID, sequence, mass, reps, rir, rpe, completedAt, setType, isWarmup
    }
}

public struct WorkoutSession: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let helmDay: HelmDay
    public let startedAt: Date
    public let finishedAt: Date?
    public let sets: [LoggedSet]

    public init(
        id: UUID = UUID(),
        helmDay: HelmDay,
        startedAt: Date,
        finishedAt: Date? = nil,
        sets: [LoggedSet] = []
    ) {
        self.id = id
        self.helmDay = helmDay
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.sets = sets
    }
}
