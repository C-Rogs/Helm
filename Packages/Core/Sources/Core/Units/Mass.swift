/// Body mass stored canonically in kilograms.
public struct Mass: Sendable, Hashable, Codable {
    public static let poundsPerKilogram = 2.204_622_621_8

    public let kilograms: Double

    public init(kilograms: Double) {
        self.kilograms = kilograms
    }

    public init(pounds: Double) {
        self.kilograms = pounds / Self.poundsPerKilogram
    }

    public var pounds: Double {
        kilograms * Self.poundsPerKilogram
    }
}
