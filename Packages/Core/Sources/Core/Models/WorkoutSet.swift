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
    public let isWarmup: Bool

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        sequence: Int,
        mass: Mass? = nil,
        reps: Int? = nil,
        rir: Int? = nil,
        rpe: Double? = nil,
        completedAt: Date,
        isWarmup: Bool = false
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.sequence = sequence
        self.mass = mass
        self.reps = reps
        self.rir = rir
        self.rpe = rpe
        self.completedAt = completedAt
        self.isWarmup = isWarmup
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
