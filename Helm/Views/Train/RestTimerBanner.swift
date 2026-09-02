import Core
import DesignSystem
import SwiftUI

struct RestTimerBanner: View {
    let endsAt: Date
    let totalSeconds: Int
    let onSkip: () -> Void
    var onAdjust: ((Int) -> Void)?
    var onRemainingSecondsChange: ((Int) -> Void)?
    /// Next exercise after the one in progress; shown as a compact dock peek.
    var upNextName: String?

    @Environment(\.helmReduceMotion) private var reduceMotion
    @Environment(\.helmTypographyEpoch) private var typographyEpoch

    var body: some View {
        let _ = typographyEpoch
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(endsAt.timeIntervalSince(context.date).rounded(.down)))
            bannerContent(remainingSeconds: remaining)
                .onChange(of: remaining) { _, newValue in
                    onRemainingSecondsChange?(newValue)
                }
                .onAppear {
                    onRemainingSecondsChange?(remaining)
                }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func bannerContent(remainingSeconds: Int) -> some View {
        let progress = RestTimerBannerProgress.remainingFraction(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds
        )
        let elapsedFraction = 1 - progress

        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(HelmColor.gaugeTrack.opacity(0.5))
                    Capsule()
                        .fill(HelmColor.accent)
                        .frame(width: elapsedFraction > 0 ? max(6, geometry.size.width * elapsedFraction) : 0)
                        .transaction(value: elapsedFraction) { transaction in
                            // Scope 1s tick to the fill only; do not slow chrome layout lifts.
                            transaction.animation = reduceMotion ? nil : .linear(duration: 1)
                        }
                }
            }
            .frame(height: HelmSpacing.xxs)
            .accessibilityHidden(true)

            if let upNextName, !upNextName.isEmpty {
                Text("UP NEXT · \(upNextName)")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Up next, \(upNextName)")
            }

            HStack(spacing: HelmSpacing.sm) {
                Text(RestTimerFormatting.mmss(remainingSeconds))
                    .helmType(.bigNumber, color: HelmColor.fg)
                    .helmNumericRoll(value: remainingSeconds)
                    .accessibilityLabel("Rest remaining \(RestTimerFormatting.mmss(remainingSeconds))")

                Spacer(minLength: HelmSpacing.xs)

                if let onAdjust {
                    Button {
                        onAdjust(-15)
                    } label: {
                        Text("−15")
                    }
                    .buttonStyle(RestDockChipStyle())
                    .accessibilityLabel("Subtract 15 seconds")

                    Button {
                        onAdjust(15)
                    } label: {
                        Text("+15")
                    }
                    .buttonStyle(RestDockChipStyle())
                    .accessibilityLabel("Add 15 seconds")
                }

                Button("Skip", action: onSkip)
                    .buttonStyle(RestDockSkipStyle())
                    .accessibilityLabel("Skip rest")
            }
        }
        .padding(.horizontal, HelmSpacing.md)
        .padding(.top, HelmSpacing.xs)
        .padding(.bottom, HelmSpacing.xs)
        .frame(maxWidth: .infinity)
    }
}

/// Primary Skip without `maxWidth: .infinity` so the timer row stays compact.
private struct RestDockSkipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .helmFont(.label)
            .foregroundStyle(HelmColor.buttonPrimaryForeground)
            .padding(.horizontal, HelmSpacing.md)
            .frame(minWidth: 72, minHeight: 44)
            .background(
                HelmColor.buttonPrimaryBackground.opacity(configuration.isPressed ? 0.85 : 1),
                in: RoundedRectangle(cornerRadius: HelmRadius.sm)
            )
    }
}

#Preview("Rest timer banner") {
    RestTimerBanner(
        endsAt: Date().addingTimeInterval(140),
        totalSeconds: 150,
        onSkip: {},
        onAdjust: { _ in },
        upNextName: "Single Arm Lateral Raise (Cable)"
    )
    .helmTheme()
}

#Preview("Rest timer banner no up next") {
    RestTimerBanner(
        endsAt: Date().addingTimeInterval(45),
        totalSeconds: 90,
        onSkip: {},
        onAdjust: { _ in }
    )
    .helmTheme()
}
