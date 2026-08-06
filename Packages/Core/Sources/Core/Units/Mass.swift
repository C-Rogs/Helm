/// Body mass stored canonically in kilograms.
public struct Mass: Sendable, Hashable, Codable {
    public static let poundsPerKilogram = 2.204_622_621_8

    public let kilograms: Double

    public init(kilograms: Double) {
        if kilograms.isFinite {
            self.kilograms = max(0, kilograms)
        } else {
            self.kilograms = 0
        }
    }

    public init(pounds: Double) {
        if pounds.isFinite {
            self.kilograms = max(0, pounds / Self.poundsPerKilogram)
        } else {
            self.kilograms = 0
        }
    }

    public var pounds: Double {
        kilograms * Self.poundsPerKilogram
    }
}
