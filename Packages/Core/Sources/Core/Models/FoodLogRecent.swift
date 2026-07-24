import Foundation

/// Denormalised recent food for fast search UI.
public struct FoodLogRecent: Sendable, Hashable, Codable {
    public let ref: FoodProductRef
    public let grams: Double
    public let servingLabel: String?
    public let lastUsedAt: Date

    public init(
        ref: FoodProductRef,
        grams: Double,
        servingLabel: String? = nil,
        lastUsedAt: Date
    ) {
        self.ref = ref
        self.grams = grams
        self.servingLabel = servingLabel
        self.lastUsedAt = lastUsedAt
    }
}
