import Foundation

/// Persisted line item for a logged meal (search, barcode, or manual food logging).
public struct MealLineItemRecord: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let mealID: UUID
    public let foodRef: FoodProductRef
    public let grams: Double
    /// Human label such as "1 pot".
    public let servingLabel: String?
    public let energyKcal: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let sortOrder: Int

    public init(
        id: UUID = UUID(),
        mealID: UUID,
        foodRef: FoodProductRef,
        grams: Double,
        servingLabel: String? = nil,
        energyKcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        sortOrder: Int
    ) {
        self.id = id
        self.mealID = mealID
        self.foodRef = foodRef
        self.grams = grams
        self.servingLabel = servingLabel
        self.energyKcal = energyKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.sortOrder = sortOrder
    }
}
