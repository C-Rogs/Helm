/// Dietary or active energy stored canonically in kilocalories.
public struct Energy: Sendable, Hashable, Codable {
    public static let kilojoulesPerKilocalorie = 4.184

    public let kilocalories: Double

    public init(kilocalories: Double) {
        self.kilocalories = kilocalories
    }

    public init(kilojoules: Double) {
        self.kilocalories = kilojoules / Self.kilojoulesPerKilocalorie
    }

    public var kilojoules: Double {
        kilocalories * Self.kilojoulesPerKilocalorie
    }
}
