import Foundation

public struct NutritionTargetsSummary: Sendable, Hashable, Codable, Equatable {
    public let caloriesKcal: Int
    public let proteinGrams: Int
    public let carbohydrateGrams: Int
    public let fatGrams: Int
    public let dayType: String

    public init(
        caloriesKcal: Int,
        proteinGrams: Int,
        carbohydrateGrams: Int,
        fatGrams: Int,
        dayType: String
    ) {
        self.caloriesKcal = caloriesKcal
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.dayType = dayType
    }
}

public struct BriefReadinessSnapshot: Sendable, Hashable, Codable, Equatable {
    public let score: Int?
    public let band: String?
    public let confidence: String?
    public let validNights: Int?

    public init(score: Int?, band: String?, confidence: String?, validNights: Int?) {
        self.score = score
        self.band = band
        self.confidence = confidence
        self.validNights = validNights
    }
}

public struct BriefPrescriptionSnapshot: Sendable, Hashable, Codable, Equatable {
    public let title: String
    public let phase: String
    public let emphasis: String?
    public let exerciseCount: Int
    public let totalSets: Int
    public let readinessAdjusted: Bool
    public let evidenceIDs: [String]

    public init(
        title: String,
        phase: String,
        emphasis: String?,
        exerciseCount: Int,
        totalSets: Int,
        readinessAdjusted: Bool,
        evidenceIDs: [String]
    ) {
        self.title = title
        self.phase = phase
        self.emphasis = emphasis
        self.exerciseCount = exerciseCount
        self.totalSets = totalSets
        self.readinessAdjusted = readinessAdjusted
        self.evidenceIDs = evidenceIDs.sorted()
    }
}

public struct BriefInputsSnapshot: Sendable, Hashable, Codable, Equatable {
    public let helmDay: HelmDay
    public let readiness: BriefReadinessSnapshot
    public let prescription: BriefPrescriptionSnapshot?
    public let nutrition: NutritionTargetsSummary

    public init(
        helmDay: HelmDay,
        readiness: BriefReadinessSnapshot,
        prescription: BriefPrescriptionSnapshot?,
        nutrition: NutritionTargetsSummary
    ) {
        self.helmDay = helmDay
        self.readiness = readiness
        self.prescription = prescription
        self.nutrition = nutrition
    }
}

public enum BriefNarrationSource: String, Sendable, Codable, Equatable {
    case engineOnly
    case coach
}

public struct StoredDailyBrief: Sendable, Hashable, Equatable {
    public let helmDay: HelmDay
    public let inputFingerprint: String
    public let engineText: String
    public let narrationText: String
    public let citationIDs: [String]
    public let source: BriefNarrationSource
    public let promptVersion: String?
    public let schemaVersion: String?
    public let updatedAt: Date

    public init(
        helmDay: HelmDay,
        inputFingerprint: String,
        engineText: String,
        narrationText: String,
        citationIDs: [String],
        source: BriefNarrationSource,
        promptVersion: String?,
        schemaVersion: String?,
        updatedAt: Date
    ) {
        self.helmDay = helmDay
        self.inputFingerprint = inputFingerprint
        self.engineText = engineText
        self.narrationText = narrationText
        self.citationIDs = citationIDs
        self.source = source
        self.promptVersion = promptVersion
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
    }

    public var displayText: String {
        source == .coach ? narrationText : engineText
    }
}
