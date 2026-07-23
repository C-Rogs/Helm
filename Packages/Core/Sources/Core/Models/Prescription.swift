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

public extension PrescribedExercise {
    /// Compact target line for Train / dashboard surfaces, e.g. `3×8 · 80kg · RPE 8`.
    var targetSummaryText: String {
        var parts: [String] = []

        let repText: String
        switch (targetRepMin, targetRepMax) {
        case let (min?, max?) where min == max:
            repText = "\(targetSets)×\(min)"
        case let (min?, max?):
            repText = "\(targetSets)×\(min)–\(max)"
        case let (min?, nil):
            repText = "\(targetSets)×\(min)"
        case let (nil, max?):
            repText = "\(targetSets)×\(max)"
        default:
            repText = "\(targetSets)×"
        }
        parts.append(repText)

        if let mass = targetMass {
            let kilograms = mass.kilograms
            let load = kilograms.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fkg", kilograms)
                : String(format: "%.1fkg", kilograms)
            parts.append(load)
        }

        if let targetRPE {
            let rpe = targetRPE.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "RPE %.0f", targetRPE)
                : String(format: "RPE %.1f", targetRPE)
            parts.append(rpe)
        }

        return parts.joined(separator: " · ")
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
