import Foundation

/// Injectable time source for testable code paths.
public protocol Clock: Sendable {
    func now() -> Date
}

/// Production clock backed by `Date`.
public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// Fixed instant for deterministic tests.
public struct FixedClock: Clock {
    public var instant: Date

    public init(instant: Date) {
        self.instant = instant
    }

    public func now() -> Date {
        instant
    }
}
