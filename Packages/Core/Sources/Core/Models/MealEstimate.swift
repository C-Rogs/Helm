import Foundation

/// Editable macro estimate from photo vision before HealthKit write-through.
public struct MealEstimate: Sendable, Equatable {
    public enum Confidence: String, Sendable, Codable, Equatable, CaseIterable {
        case low
        case medium
        case high
    }

    /// Direct vision macro estimate for comparison when CoFID grounding diverges.
    public struct VisionMacroComparison: Sendable, Equatable {
        public var caloriesKcal: Double
        public var proteinG: Double
        public var carbsG: Double
        public var fatG: Double
        public var confidence: Confidence

        public init(
            caloriesKcal: Double,
            proteinG: Double,
            carbsG: Double,
            fatG: Double,
            confidence: Confidence
        ) {
            self.caloriesKcal = caloriesKcal
            self.proteinG = proteinG
            self.carbsG = carbsG
            self.fatG = fatG
            self.confidence = confidence
        }
    }

    public var description: String
    public var caloriesKcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public let confidence: Confidence
    /// Per-ingredient breakdown from grounded photo pipeline; empty for legacy v1 artefacts.
    public var lineItems: [MealLineItem]
    /// Optional parallel estimate from vision-only macro prompt (not CoFID grounded).
    public var visionDirectEstimate: VisionMacroComparison?
    /// Human-readable CoFID grounding issues (generic fallback, divergence, etc.).
    public var groundingWarnings: [String]
    /// JSON audit of vision decomposition for Diagnostics export.
    public var decompositionAuditJSON: String?

    public init(
        description: String,
        caloriesKcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        confidence: Confidence,
        lineItems: [MealLineItem] = [],
        visionDirectEstimate: VisionMacroComparison? = nil,
        groundingWarnings: [String] = [],
        decompositionAuditJSON: String? = nil
    ) {
        self.description = description
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.confidence = confidence
        self.lineItems = lineItems
        self.visionDirectEstimate = visionDirectEstimate
        self.groundingWarnings = groundingWarnings
        self.decompositionAuditJSON = decompositionAuditJSON
    }
}
