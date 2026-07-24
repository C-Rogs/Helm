import Foundation

public struct SessionAdjustmentPayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let rationale: String
    public let operations: [SessionAdjustmentOperation]

    public init(schemaVersion: String, rationale: String, operations: [SessionAdjustmentOperation]) {
        self.schemaVersion = schemaVersion
        self.rationale = rationale
        self.operations = operations
    }
}

public struct SessionAdjustmentOperation: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case swap
        case reorder
        case adjustSets
    }

    public let kind: Kind
    public let fromExerciseID: String?
    public let toExerciseID: String?
    public let excludeExerciseIDs: [String]?
    public let orderedExerciseIDs: [String]?
    public let exerciseID: String?
    public let setDelta: Int?

    public init(
        kind: Kind,
        fromExerciseID: String? = nil,
        toExerciseID: String? = nil,
        excludeExerciseIDs: [String]? = nil,
        orderedExerciseIDs: [String]? = nil,
        exerciseID: String? = nil,
        setDelta: Int? = nil
    ) {
        self.kind = kind
        self.fromExerciseID = fromExerciseID
        self.toExerciseID = toExerciseID
        self.excludeExerciseIDs = excludeExerciseIDs
        self.orderedExerciseIDs = orderedExerciseIDs
        self.exerciseID = exerciseID
        self.setDelta = setDelta
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
