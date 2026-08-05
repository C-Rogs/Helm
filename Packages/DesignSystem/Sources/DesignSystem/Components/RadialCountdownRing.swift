import SwiftUI

/// Full-circle countdown ring with centered time readout and instrument bezel.
public struct RadialCountdownRing: View {
    private let remainingSeconds: Int
    private let remainingFraction: Double
    private let lineWidth: CGFloat

    @Environment(\.helmReduceMotion) private var reduceMotion
    @Environment(\.helmSkin) private var skin

    public init(
        remainingSeconds: Int,
        remainingFraction: Double,
        lineWidth: CGFloat = 14
    ) {
        self.remainingSeconds = max(0, remainingSeconds)
        self.remainingFraction = min(1, max(0, remainingFraction))
        self.lineWidth = max(0, lineWidth)
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(HelmColor.surfaceElevated.opacity(skin == .signal ? 0.55 : 0.9))
                .overlay {
                    Circle()
                        .strokeBorder(HelmColor.hairline, lineWidth: 1)
                }
                .shadow(
                    color: HelmColor.accent.opacity(remainingFraction > 0 ? 0.12 : 0),
                    radius: reduceMotion ? 0 : 18,
                    y: reduceMotion ? 0 : 4
                )

            Circle()
                .inset(by: lineWidth * 0.35)
                .stroke(HelmColor.gaugeTrack.opacity(0.85), lineWidth: lineWidth)

            Circle()
                .inset(by: lineWidth * 0.35)
                .trim(from: 0, to: remainingFraction)
                .stroke(
                    HelmColor.accent,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: remainingFraction)
                .shadow(
                    color: HelmColor.accent.opacity(reduceMotion ? 0 : 0.35),
                    radius: reduceMotion ? 0 : 8
                )

            VStack(spacing: HelmSpacing.xxs) {
                Text(RestTimerFormatting.mmss(remainingSeconds))
                    .helmType(.bigNumber, color: HelmColor.fg)
                    .helmNumericRoll(value: remainingSeconds)
                Text("REST")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time remaining \(RestTimerFormatting.mmss(remainingSeconds))")
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(HelmSpacing.sm)
    }
}

#Preview("Radial countdown ring") {
    RadialCountdownRing(remainingSeconds: 72, remainingFraction: 0.8)
        .frame(width: 220, height: 220)
        .padding()
        .helmTheme()
        .helmScreenBackground()
}
