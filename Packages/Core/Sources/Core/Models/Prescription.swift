import Foundation

public struct PrescribedExercise: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let exerciseID: String
    public let order: Int
    public let targetSets: Int
    public let targetRepMin: Int?
    public let targetRepMax: Int?
    public let targetMass: Mass?
    public let targetRPE: Double?
    public let rationale: String?
    public let evidenceIDs: [String]

    public init(
        id: UUID = UUID(),
        exerciseID: String,
        order: Int,
        targetSets: Int,
        targetRepMin: Int? = nil,
        targetRepMax: Int? = nil,
        targetMass: Mass? = nil,
        targetRPE: Double? = nil,
        rationale: String? = nil,
        evidenceIDs: [String] = []
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.order = order
        self.targetSets = targetSets
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.targetMass = targetMass
        self.targetRPE = targetRPE
        self.rationale = rationale
        self.evidenceIDs = evidenceIDs
    }
}

public struct SessionPrescription: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let helmDay: HelmDay
    public let exercises: [PrescribedExercise]

    public init(
        id: UUID = UUID(),
        helmDay: HelmDay,
        exercises: [PrescribedExercise]
    ) {
        self.id = id
        self.helmDay = helmDay
        self.exercises = exercises
    }
}
