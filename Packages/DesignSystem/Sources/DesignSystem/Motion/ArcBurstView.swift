import SwiftUI

/// Restrained state-colored arc burst for PR celebration.
public struct ArcBurstView: View {
    private let state: HelmState
    private let isActive: Bool

    @Environment(\.helmReduceMotion) private var reduceMotion
    @State private var burstProgress: Double = 0

    public init(state: HelmState = .primed, isActive: Bool = true) {
        self.state = state
        self.isActive = isActive
    }

    public var body: some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { index in
                burstArc(index: index)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { playBurstIfNeeded() }
        .onChange(of: isActive) { _, active in
            if active { playBurstIfNeeded() }
        }
    }

    private func burstArc(index: Int) -> some View {
        let rotation = 135.0 + Double(index) * 24.0
        let expansion = reduceMotion ? 1 : 0.72 + (0.28 * burstProgress)
        let opacity = reduceMotion ? (isActive ? 0.45 : 0) : max(0, 1 - burstProgress) * 0.85

        return Circle()
            .trim(from: 0, to: 0.22)
            .stroke(
                HelmColor.color(for: state).opacity(opacity),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
            .rotationEffect(.degrees(rotation))
            .scaleEffect(expansion)
            .opacity(isActive ? 1 : 0)
    }

    private func playBurstIfNeeded() {
        guard isActive else {
            burstProgress = 0
            return
        }

        if reduceMotion {
            burstProgress = 1
            return
        }

        burstProgress = 0
        withAnimation(HelmMotion.revealAnimation) {
            burstProgress = 1
        }
    }
}

#if DEBUG
#Preview("Arc burst") {
    ZStack {
        ArcGauge(value: 88, state: .primed) {
            Text("PR")
                .helmType(.heroNumber, color: HelmColor.primed)
        }
        .frame(width: 180)

        ArcBurstView(state: .primed)
            .frame(width: 220, height: 220)
    }
    .padding()
    .helmTheme()
}

#Preview("Arc burst reduce motion") {
    ArcBurstView(state: .ready, isActive: true)
        .frame(width: 220, height: 220)
        .helmTheme()
        .environment(\.helmReduceMotion, true)
}
#endif
