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

    public var body: some View {
        ArcGauge(value: displayValue, range: range, state: state) {
            center(displayValue)
        }
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
