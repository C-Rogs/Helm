import Foundation

/// Editable macro estimate from photo vision before HealthKit write-through.
public struct MealEstimate: Sendable, Equatable {
    public enum Confidence: String, Sendable, Codable, Equatable, CaseIterable {
        case low
        case medium
        case high
    }

    public var description: String
    public var caloriesKcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public let confidence: Confidence
    /// Per-ingredient breakdown from grounded photo pipeline; empty for legacy v1 artefacts.
    public var lineItems: [MealLineItem]

    public init(
        description: String,
        caloriesKcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        confidence: Confidence,
        lineItems: [MealLineItem] = []
    ) {
        self.description = description
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.confidence = confidence
        self.lineItems = lineItems
    }
}
