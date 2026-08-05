import SwiftUI

/// Self-drawing arc used for onboarding welcome and payoff moments.
public struct ArcDrawGauge<Center: View>: View {
    private let targetValue: Double
    private let range: ClosedRange<Double>
    private let state: HelmState
    private let animate: Bool
    private let reduceMotion: Bool
    private let center: Center

    @State private var displayValue: Double = 0

    public init(
        targetValue: Double,
        range: ClosedRange<Double> = 0 ... 100,
        state: HelmState,
        animate: Bool = true,
        reduceMotion: Bool,
        @ViewBuilder center: () -> Center
    ) {
        self.targetValue = targetValue
        self.range = range
        self.state = state
        self.animate = animate
        self.reduceMotion = reduceMotion
        self.center = center()
    }

    public var body: some View {
        let progress = range.upperBound > range.lowerBound
            ? (displayValue - range.lowerBound) / (range.upperBound - range.lowerBound)
            : 0

        ArcGauge(value: displayValue, range: range, state: state) {
            center
        }
        .arcStateBloom(progress: progress, state: state, reduceMotion: reduceMotion)
        .onAppear(perform: beginDrawIfNeeded)
        .onChange(of: animate) { _, shouldAnimate in
            if shouldAnimate { beginDrawIfNeeded() }
        }
    }

    private func beginDrawIfNeeded() {
        guard animate else {
            displayValue = targetValue
            return
        }

        if HelmMotion.shouldAnimateReveal(reduceMotion: reduceMotion) {
            displayValue = 0
            withAnimation(HelmMotion.animation(HelmMotion.revealAnimation, reduceMotion: reduceMotion)) {
                displayValue = targetValue
            }
        } else {
            displayValue = targetValue
        }
    }
}

#if DEBUG
#Preview("Arc draw gauge") {
    ArcDrawGauge(targetValue: 72, state: .ready, reduceMotion: false) {
        VStack(spacing: HelmSpacing.xxs) {
            Text("Signal")
                .helmType(.heroNumber)
            Text("READY")
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
    }
    .frame(maxWidth: 220)
    .padding()
    .helmTheme()
}
#endif
