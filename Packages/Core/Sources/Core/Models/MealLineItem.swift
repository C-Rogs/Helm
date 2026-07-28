import Foundation

/// One CoFID-grounded ingredient line in a photo meal estimate.
public struct MealLineItem: Sendable, Equatable, Codable, Identifiable {
    public var id: String { "\(name)-\(grams)" }

    public var name: String
    public var grams: Double
    public var caloriesKcal: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var usdaMatchID: String?
    public var matchConfidence: MealEstimate.Confidence
    /// CoFID record description used for macro math (nil when scaled without re-resolve).
    public var cofidDescription: String?

    public init(
        name: String,
        grams: Double,
        caloriesKcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        usdaMatchID: String? = nil,
        matchConfidence: MealEstimate.Confidence,
        cofidDescription: String? = nil
    ) {
        self.name = name
        self.grams = grams
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.usdaMatchID = usdaMatchID
        self.matchConfidence = matchConfidence
        self.cofidDescription = cofidDescription
    }

    public var usesGenericCofidFallback: Bool {
        usdaMatchID == "generic_mixed"
    }
}
