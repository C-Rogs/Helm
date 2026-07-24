import Foundation

/// One USDA-grounded ingredient line in a photo meal estimate.
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

    public init(
        name: String,
        grams: Double,
        caloriesKcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        usdaMatchID: String? = nil,
        matchConfidence: MealEstimate.Confidence
    ) {
        self.name = name
        self.grams = grams
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.usdaMatchID = usdaMatchID
        self.matchConfidence = matchConfidence
    }
}
