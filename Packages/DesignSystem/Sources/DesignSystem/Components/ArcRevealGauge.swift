import SwiftUI

/// Arc gauge with the readiness reveal timeline: sweep, count-up center, then detail fade-in.
public struct ArcRevealGauge<Center: View>: View {
    private let targetValue: Double
    private let range: ClosedRange<Double>
    private let state: HelmState
    private let reveal: Bool
    private let reduceMotion: Bool
    private let onRevealStart: (() -> Void)?
    private let center: (Double) -> Center
    @Binding private var detailsVisible: Bool

    @State private var displayValue: Double = 0

    public init(
        targetValue: Double,
        range: ClosedRange<Double> = 0 ... 100,
        state: HelmState,
        reveal: Bool,
        reduceMotion: Bool,
        detailsVisible: Binding<Bool>,
        onRevealStart: (() -> Void)? = nil,
        @ViewBuilder center: @escaping (Double) -> Center
    ) {
        self.targetValue = targetValue
        self.range = range
        self.state = state
        self.reveal = reveal
        self.reduceMotion = reduceMotion
        _detailsVisible = detailsVisible
        self.onRevealStart = onRevealStart
        self.center = center
    }

    private var revealProgress: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        let clamped = min(max(displayValue, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    public var body: some View {
        ArcGauge(value: displayValue, range: range, state: state) {
            center(displayValue)
        }
        .arcStateBloom(progress: revealProgress, state: state, reduceMotion: reduceMotion)
        .onAppear(perform: beginRevealIfNeeded)
        .onChange(of: targetValue) { _, newValue in
            guard reveal == false else { return }
            displayValue = newValue
        }
        .onChange(of: reveal) { _, shouldReveal in
            guard shouldReveal else {
                displayValue = targetValue
                detailsVisible = true
                return
            }
            beginRevealIfNeeded()
        }
    }

    private func beginRevealIfNeeded() {
        guard reveal else {
            displayValue = targetValue
            detailsVisible = true
            return
        }

        if HelmMotion.shouldAnimateReveal(reduceMotion: reduceMotion) {
            displayValue = 0
            detailsVisible = false
            onRevealStart?()

            withAnimation(HelmMotion.revealAnimation) {
                displayValue = targetValue
            }

            let detailsDelay = HelmMotion.revealDuration(reduceMotion: false) - 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + max(detailsDelay, 0)) {
                withAnimation(HelmMotion.standardAnimation) {
                    detailsVisible = true
                }
            }
        } else {
            displayValue = targetValue
            detailsVisible = true
            onRevealStart?()
        }
    }
}

public extension View {
    /// Fades and lifts readiness detail blocks during the reveal tail.
    func readinessDetailsReveal(visible: Bool, reduceMotion: Bool) -> some View {
        modifier(ReadinessDetailsRevealModifier(visible: visible, reduceMotion: reduceMotion))
    }

    /// Staggers contributor rows in during the reveal tail.
    func readinessContributorReveal(
        visible: Bool,
        index: Int,
        reduceMotion: Bool
    ) -> some View {
        modifier(
            ReadinessContributorRevealModifier(
                visible: visible,
                index: index,
                reduceMotion: reduceMotion
            )
        )
    }
}

private struct ReadinessDetailsRevealModifier: ViewModifier {
    let visible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 8)
            .animation(
                HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: reduceMotion),
                value: visible
            )
    }
}

private struct ReadinessContributorRevealModifier: ViewModifier {
    let visible: Bool
    let index: Int
    let reduceMotion: Bool

    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear { updateAppearance(visible) }
            .onChange(of: visible) { _, isVisible in
                updateAppearance(isVisible)
            }
    }

    private func updateAppearance(_ isVisible: Bool) {
        guard isVisible else {
            appeared = false
            return
        }

        let delay = HelmMotion.staggerDelay(index: index, step: 0.05, reduceMotion: reduceMotion)
        if delay == 0 {
            withAnimation(HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: reduceMotion)) {
                appeared = true
            }
            return
        }

        appeared = false
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: reduceMotion)) {
                appeared = true
            }
        }
    }
}

#if DEBUG
#Preview("Arc reveal") {
    ArcRevealGauge(
        targetValue: 72,
        state: .ready,
        reveal: true,
        reduceMotion: false,
        detailsVisible: .constant(false)
    ) { value in
        VStack(spacing: HelmSpacing.xxs) {
            HelmNumericText(Int(value.rounded()))
                .helmType(.heroNumber)
            Text(HelmState.ready.label)
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
    }
    .frame(maxWidth: 220)
    .padding()
    .helmTheme()
}
#endif
