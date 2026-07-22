import Foundation

/// Pure once-per-day reveal gate keyed by a stable day string (e.g. `HelmDay.formatted`).
public struct DailyRevealGate: Equatable, Sendable {
    public private(set) var lastRevealedDay: String?

    public init(lastRevealedDay: String? = nil) {
        self.lastRevealedDay = lastRevealedDay
    }

    public func shouldReveal(for day: String) -> Bool {
        lastRevealedDay != day
    }

    public mutating func markRevealed(for day: String) {
        lastRevealedDay = day
    }
}
