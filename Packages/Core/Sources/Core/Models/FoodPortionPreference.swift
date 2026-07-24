import Foundation

/// Last-used portion for a food reference (portion memory).
public struct FoodPortionPreference: Sendable, Hashable, Codable {
    public let foodRef: FoodProductRef
    public let grams: Double
    public let servingLabel: String?
    public let lastUsedAt: Date

    public init(
        foodRef: FoodProductRef,
        grams: Double,
        servingLabel: String? = nil,
        lastUsedAt: Date
    ) {
        self.foodRef = foodRef
        self.grams = grams
        self.servingLabel = servingLabel
        self.lastUsedAt = lastUsedAt
    }
}
