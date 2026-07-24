import Foundation

/// Cached product snapshot from CoFID, OFF, or custom food.
public struct FoodProductCacheEntry: Sendable, Hashable, Codable {
    public let ref: FoodProductRef
    public let per100gKcal: Double
    public let per100gProteinG: Double
    public let per100gCarbsG: Double
    public let per100gFatG: Double
    /// Optional raw OFF JSON for fields not modelled here.
    public let snapshotJSON: String?
    public let updatedAt: Date

    public init(
        ref: FoodProductRef,
        per100gKcal: Double,
        per100gProteinG: Double,
        per100gCarbsG: Double,
        per100gFatG: Double,
        snapshotJSON: String? = nil,
        updatedAt: Date
    ) {
        self.ref = ref
        self.per100gKcal = per100gKcal
        self.per100gProteinG = per100gProteinG
        self.per100gCarbsG = per100gCarbsG
        self.per100gFatG = per100gFatG
        self.snapshotJSON = snapshotJSON
        self.updatedAt = updatedAt
    }
}
