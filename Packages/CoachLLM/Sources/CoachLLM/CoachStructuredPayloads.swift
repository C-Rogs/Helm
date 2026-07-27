import Foundation

public struct SessionAdjustmentPayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let reply: String
    public let rationale: String?
    public let operations: [SessionAdjustmentOperation]

    /// v2 and unified initializer.
    public init(
        schemaVersion: String,
        reply: String,
        rationale: String? = nil,
        operations: [SessionAdjustmentOperation]
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
        self.rationale = rationale
        self.operations = operations
    }

    /// v1 compatibility: rationale doubles as chat reply.
    public init(
        schemaVersion: String,
        rationale: String,
        operations: [SessionAdjustmentOperation]
    ) {
        self.init(
            schemaVersion: schemaVersion,
            reply: rationale,
            rationale: rationale,
            operations: operations
        )
    }

    public var bannerReason: String {
        rationale ?? reply
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        operations = try container.decode([SessionAdjustmentOperation].self, forKey: .operations)

        if let decodedReply = try container.decodeIfPresent(String.self, forKey: .reply) {
            reply = decodedReply
            rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        } else {
            let legacyRationale = try container.decode(String.self, forKey: .rationale)
            reply = legacyRationale
            rationale = legacyRationale
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(reply, forKey: .reply)
        try container.encodeIfPresent(rationale, forKey: .rationale)
        try container.encode(operations, forKey: .operations)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reply
        case rationale
        case operations
    }
}

public struct SessionAdjustmentOperation: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case swap
        case reorder
        case adjustSets
        case adjustLoad
        case adjustRPE
    }

    public let kind: Kind
    public let fromExerciseID: String?
    public let toExerciseID: String?
    public let excludeExerciseIDs: [String]?
    public let orderedExerciseIDs: [String]?
    public let exerciseID: String?
    public let setDelta: Int?
    public let massDeltaKg: Double?
    public let targetMassKg: Double?
    public let rpeDelta: Double?
    public let targetRPE: Double?

    public init(
        kind: Kind,
        fromExerciseID: String? = nil,
        toExerciseID: String? = nil,
        excludeExerciseIDs: [String]? = nil,
        orderedExerciseIDs: [String]? = nil,
        exerciseID: String? = nil,
        setDelta: Int? = nil,
        massDeltaKg: Double? = nil,
        targetMassKg: Double? = nil,
        rpeDelta: Double? = nil,
        targetRPE: Double? = nil
    ) {
        self.kind = kind
        self.fromExerciseID = fromExerciseID
        self.toExerciseID = toExerciseID
        self.excludeExerciseIDs = excludeExerciseIDs
        self.orderedExerciseIDs = orderedExerciseIDs
        self.exerciseID = exerciseID
        self.setDelta = setDelta
        self.massDeltaKg = massDeltaKg
        self.targetMassKg = targetMassKg
        self.rpeDelta = rpeDelta
        self.targetRPE = targetRPE
    }
}

public struct MealEstimatePayload: Codable, Sendable, Equatable {
    public enum Confidence: String, Codable, Sendable, Equatable {
        case low
        case medium
        case high
    }

    public let schemaVersion: String
    public let description: String
    public let caloriesKcal: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let confidence: Confidence

    public init(
        schemaVersion: String,
        description: String,
        caloriesKcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        confidence: Confidence
    ) {
        self.schemaVersion = schemaVersion
        self.description = description
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.confidence = confidence
    }
}

public struct MealDecompositionPayload: Codable, Sendable, Equatable {
    public enum Confidence: String, Codable, Sendable, Equatable {
        case low
        case medium
        case high
    }

    public struct Item: Codable, Sendable, Equatable {
        public let name: String
        public let estimatedGrams: Double
        public let confidence: Confidence

        public init(name: String, estimatedGrams: Double, confidence: Confidence) {
            self.name = name
            self.estimatedGrams = estimatedGrams
            self.confidence = confidence
        }
    }

    public let schemaVersion: String
    public let mealDescription: String
    public let items: [Item]
    public let implicitFats: [Item]
    public let portionNotes: String?

    public init(
        schemaVersion: String,
        mealDescription: String,
        items: [Item],
        implicitFats: [Item] = [],
        portionNotes: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.mealDescription = mealDescription
        self.items = items
        self.implicitFats = implicitFats
        self.portionNotes = portionNotes
    }
}

public struct MealDecomposition: Sendable, Equatable {
    public let mealDescription: String
    public let items: [MealDecompositionPayload.Item]
    public let implicitFats: [MealDecompositionPayload.Item]
    public let portionNotes: String?

    public init(payload: MealDecompositionPayload) {
        mealDescription = payload.mealDescription
        items = payload.items
        implicitFats = payload.implicitFats
        portionNotes = payload.portionNotes
    }
}

public struct MorningBriefPayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let narration: String
    public let citationIDs: [String]

    public init(schemaVersion: String, narration: String, citationIDs: [String]) {
        self.schemaVersion = schemaVersion
        self.narration = narration
        self.citationIDs = citationIDs
    }
}
