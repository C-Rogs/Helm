import Foundation

/// Saved meal template for one-tap logging.
public struct MealTemplate: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let bucket: MealBucket
    /// Snapshot portions from the last saved template state.
    public let lineItems: [MealLineItem]
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        bucket: MealBucket,
        lineItems: [MealLineItem],
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.bucket = bucket
        self.lineItems = lineItems
        self.updatedAt = updatedAt
    }
}
