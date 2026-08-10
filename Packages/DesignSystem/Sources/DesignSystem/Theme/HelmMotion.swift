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

    public static func staggerDelay(
        index: Int,
        step: TimeInterval = 0.04,
        baseDelay: TimeInterval = 0,
        reduceMotion: Bool
    ) -> TimeInterval {
        reduceMotion ? 0 : baseDelay + step * Double(index)
    }

    public static func usesShimmer(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    public static var pulseAnimation: Animation {
        revealAnimation
    }
}

public extension EnvironmentValues {
    @Entry var helmReduceMotion: Bool = false
    /// Extra delay before staggered appear (e.g. after tab liquid-glass morph).
    @Entry var helmStaggerBaseDelay: TimeInterval = 0
}
