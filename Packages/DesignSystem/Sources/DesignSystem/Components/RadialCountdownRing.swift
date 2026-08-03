import SwiftUI

/// Full-circle countdown ring with centered time readout.
public struct RadialCountdownRing: View {
    private let remainingSeconds: Int
    private let remainingFraction: Double
    private let lineWidth: CGFloat

    @Environment(\.helmReduceMotion) private var reduceMotion

    public init(
        remainingSeconds: Int,
        remainingFraction: Double,
        lineWidth: CGFloat = 12
    ) {
        self.remainingSeconds = max(0, remainingSeconds)
        self.remainingFraction = min(1, max(0, remainingFraction))
        self.lineWidth = max(0, lineWidth)
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(HelmColor.gaugeTrack, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: remainingFraction)
                .stroke(
                    HelmColor.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: remainingFraction)

            Text(RestTimerFormatting.mmss(remainingSeconds))
                .helmType(.bigNumber, color: HelmColor.fg)
                .monospacedDigit()
                .accessibilityLabel("Time remaining \(RestTimerFormatting.mmss(remainingSeconds))")
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

#Preview("Radial countdown ring") {
    RadialCountdownRing(remainingSeconds: 72, remainingFraction: 0.8)
        .frame(width: 220, height: 220)
        .padding()
        .helmTheme()
        .helmScreenBackground()
}
