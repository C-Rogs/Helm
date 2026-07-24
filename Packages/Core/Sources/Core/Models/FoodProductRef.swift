import Foundation

/// Stable food identity across CoFID, Open Food Facts, and user custom entries.
public struct FoodProductRef: Sendable, Hashable, Codable {
    public enum Origin: String, Sendable, Codable, CaseIterable {
        case cofid
        case openFoodFacts
        case custom
    }

    public let origin: Origin
    /// CoFID code, OFF barcode, or custom UUID.
    public let externalID: String
    public let displayName: String

    public init(origin: Origin, externalID: String, displayName: String) {
        self.origin = origin
        self.externalID = externalID
        self.displayName = displayName
    }

    /// Composite cache key: `origin:externalID`.
    public var cacheKey: String {
        "\(origin.rawValue):\(externalID)"
    }

    public init?(cacheKey: String, displayName: String) {
        let parts = cacheKey.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let origin = Origin(rawValue: String(parts[0])) else {
            return nil
        }
        self.origin = origin
        self.externalID = String(parts[1])
        self.displayName = displayName
    }
}
