import SwiftUI

/// Subtle state-tint radial bloom behind arc gauges during reveal.
public struct ArcStateBloom: View {
    private let progress: Double
    private let state: HelmState
    private let reduceMotion: Bool

    public init(progress: Double, state: HelmState, reduceMotion: Bool) {
        self.progress = min(max(progress, 0), 1)
        self.state = state
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        HelmColor.color(for: state).opacity(0.28 * progress),
                        HelmColor.color(for: state).opacity(0.08 * progress),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 120
                )
            )
            .scaleEffect(reduceMotion ? 1 : 0.88 + (0.12 * progress))
            .opacity(reduceMotion ? (progress > 0 ? 0.35 : 0) : progress)
            .animation(
                HelmMotion.animation(HelmMotion.revealAnimation, reduceMotion: reduceMotion),
                value: progress
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

public extension View {
    /// Places a state-colored bloom behind arc content.
    func arcStateBloom(
        progress: Double,
        state: HelmState,
        reduceMotion: Bool
    ) -> some View {
        background {
            ArcStateBloom(progress: progress, state: state, reduceMotion: reduceMotion)
        }
    }
}

#if DEBUG
#Preview("Arc state bloom") {
    ArcStateBloom(progress: 0.72, state: .ready, reduceMotion: false)
        .frame(width: 220, height: 220)
        .helmTheme()
}
#endif
