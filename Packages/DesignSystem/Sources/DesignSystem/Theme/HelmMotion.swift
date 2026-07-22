import SwiftUI

public enum HelmMotion {
    public static let quick: TimeInterval = 0.18
    public static let standard: TimeInterval = 0.28
    public static let reveal: TimeInterval = 0.9

    public static let settleResponse: Double = 0.42
    public static let settleDamping: Double = 0.82

    public static var quickAnimation: Animation {
        .easeOut(duration: quick)
    }

    public static var standardAnimation: Animation {
        .easeInOut(duration: standard)
    }

    public static var settleAnimation: Animation {
        .spring(response: settleResponse, dampingFraction: settleDamping)
    }

    public static var revealAnimation: Animation {
        .easeOut(duration: reveal)
    }

    public static func animation(
        _ preferred: Animation,
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion ? .easeOut(duration: quick) : preferred
    }

    public static func revealDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? quick : reveal
    }

    public static func shouldAnimateReveal(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

public extension EnvironmentValues {
    @Entry var helmReduceMotion: Bool = false
}
