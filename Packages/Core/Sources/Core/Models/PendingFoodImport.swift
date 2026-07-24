import Foundation

/// Offline or failed branded lookup queued for background resolution.
public struct PendingFoodImport: Sendable, Equatable, Codable, Identifiable {
    public enum Status: String, Sendable, Codable, CaseIterable {
        case pending
        case resolved
        case failed
    }

    public let id: UUID
    public let createdAt: Date
    public let barcode: String?
    public let photoMealID: UUID?
    public let provisionalLineItems: [MealLineItem]
    public let status: Status

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        barcode: String? = nil,
        photoMealID: UUID? = nil,
        provisionalLineItems: [MealLineItem] = [],
        status: Status = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.barcode = barcode
        self.photoMealID = photoMealID
        self.provisionalLineItems = provisionalLineItems
        self.status = status
    }
}
