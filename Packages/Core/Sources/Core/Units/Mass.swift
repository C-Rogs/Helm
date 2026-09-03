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

    /// Zero (or non-finite) kg is treated as unset for working loads. Coach/engine
    /// paths sometimes coerce a missing weight to `0`, which must not block
    /// profile fill or next-set carry the way a real load would.
    public var isUnsetWorkingLoad: Bool {
        !kilograms.isFinite || kilograms <= 0
    }

    /// Positive working load in kg, or nil when unset/zero.
    public var meaningfulWorkingKilograms: Double? {
        isUnsetWorkingLoad ? nil : kilograms
    }

    /// Returns a mass only when `kilograms` is a real positive working load.
    public static func workingLoad(kilograms: Double) -> Mass? {
        guard kilograms.isFinite, kilograms > 0 else { return nil }
        return Mass(kilograms: kilograms)
    }
}

extension Optional where Wrapped == Mass {
    public var hasMeaningfulWorkingLoad: Bool {
        map { !$0.isUnsetWorkingLoad } ?? false
    }

    public var meaningfulWorkingKilograms: Double? {
        flatMap(\.meaningfulWorkingKilograms)
    }
}
