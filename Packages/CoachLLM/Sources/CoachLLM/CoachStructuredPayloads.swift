import Core
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
        case addExercise
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
    public let loadAdjustmentIntent: LoadAdjustmentIntent?
    public let targetSets: Int?

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
        targetRPE: Double? = nil,
        loadAdjustmentIntent: LoadAdjustmentIntent? = nil,
        targetSets: Int? = nil
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
        self.loadAdjustmentIntent = loadAdjustmentIntent
        self.targetSets = targetSets
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

public struct FoodLogPayload: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable, Equatable {
        case log
        case edit
        case delete
    }

    public let schemaVersion: String
    public let reply: String
    public let action: Action
    public let mealID: String?
    public let description: String?
    public let bucket: String?
    public let caloriesKcal: Double?
    public let proteinG: Double?
    public let carbsG: Double?
    public let fatG: Double?
    public let helmDay: String?

    public init(
        schemaVersion: String,
        reply: String,
        action: Action,
        mealID: String? = nil,
        description: String? = nil,
        bucket: String? = nil,
        caloriesKcal: Double? = nil,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatG: Double? = nil,
        helmDay: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
        self.action = action
        self.mealID = mealID
        self.description = description
        self.bucket = bucket
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.helmDay = helmDay
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

/// Coach-rendered chart for chat when the athlete asks for a visual.
public struct ChartPayload: Codable, Sendable, Equatable {
    public struct Point: Codable, Sendable, Equatable, Identifiable {
        public var id: String { "\(label)-\(value)" }
        public let label: String
        public let value: Double

        public init(label: String, value: Double) {
            self.label = label
            self.value = value
        }
    }

    public let schemaVersion: String
    public let reply: String
    public let title: String
    public let unit: String?
    public let points: [Point]

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.chartV1.rawValue,
        reply: String,
        title: String,
        unit: String? = nil,
        points: [Point]
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
        self.title = title
        self.unit = unit
        self.points = points
    }
}

public enum ChartPayloadParser: Sendable {
    public static func parse(from text: String) -> ChartPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .chartV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ChartPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.chartV1.rawValue,
              !payload.points.isEmpty
        else {
            return nil
        }
        return payload
    }
}

public enum CoachChatChartSnapshot: Sendable {
    public static func text(for payload: ChartPayload) -> String {
        var lines = [
            "# Chart",
            "## Title",
            payload.title,
            "## Unit",
            payload.unit ?? "none",
            "## Points"
        ]
        for point in payload.points {
            lines.append("- \(point.label)=\(formatValue(point.value))")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatValue(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
