import Foundation

public struct PrescribedExercise: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let exerciseID: String
    public let order: Int
    /// Working (hard) sets only. Warm-ups live in `warmupSets` and do not count toward volume.
    public let targetSets: Int
    /// Planned warm-up sets. Never counted as hard-set volume.
    public let warmupSets: Int
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
        warmupSets: Int = 0,
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
        self.warmupSets = max(0, warmupSets)
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.targetMass = targetMass
        self.targetRPE = targetRPE
        self.rationale = rationale
        self.evidenceIDs = evidenceIDs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        exerciseID = try container.decode(String.self, forKey: .exerciseID)
        order = try container.decode(Int.self, forKey: .order)
        targetSets = try container.decode(Int.self, forKey: .targetSets)
        // Pre-sidecar caches omit this key; default keeps same-day UserDefaults loads alive.
        warmupSets = max(0, try container.decodeIfPresent(Int.self, forKey: .warmupSets) ?? 0)
        targetRepMin = try container.decodeIfPresent(Int.self, forKey: .targetRepMin)
        targetRepMax = try container.decodeIfPresent(Int.self, forKey: .targetRepMax)
        targetMass = try container.decodeIfPresent(Mass.self, forKey: .targetMass)
        targetRPE = try container.decodeIfPresent(Double.self, forKey: .targetRPE)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        evidenceIDs = try container.decodeIfPresent([String].self, forKey: .evidenceIDs) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encode(order, forKey: .order)
        try container.encode(targetSets, forKey: .targetSets)
        try container.encode(warmupSets, forKey: .warmupSets)
        try container.encodeIfPresent(targetRepMin, forKey: .targetRepMin)
        try container.encodeIfPresent(targetRepMax, forKey: .targetRepMax)
        try container.encodeIfPresent(targetMass, forKey: .targetMass)
        try container.encodeIfPresent(targetRPE, forKey: .targetRPE)
        try container.encodeIfPresent(rationale, forKey: .rationale)
        try container.encode(evidenceIDs, forKey: .evidenceIDs)
    }

    private enum CodingKeys: String, CodingKey {
        case id, exerciseID, order, targetSets, warmupSets
        case targetRepMin, targetRepMax, targetMass, targetRPE, rationale, evidenceIDs
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
            repText = "\(targetSets)×\(min)-\(max)"
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
    public let title: String?
    public let exercises: [PrescribedExercise]

    public init(
        id: UUID = UUID(),
        helmDay: HelmDay,
        title: String? = nil,
        exercises: [PrescribedExercise]
    ) {
        self.id = id
        self.helmDay = helmDay
        self.title = title
        self.exercises = exercises
    }
}
