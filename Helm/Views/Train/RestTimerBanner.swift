import Core
import DesignSystem
import SwiftUI

struct RestTimerBanner: View {
    let endsAt: Date
    let totalSeconds: Int
    let onSkip: () -> Void
    var onAdjust: ((Int) -> Void)?
    var onRemainingSecondsChange: ((Int) -> Void)?

    @Environment(\.helmReduceMotion) private var reduceMotion

    var body: some View {
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
    }

    @ViewBuilder
    private func bannerContent(remainingSeconds: Int) -> some View {
        let progress = RestTimerBannerProgress.remainingFraction(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds
        )
        let elapsedFraction = 1 - progress

        VStack(spacing: HelmSpacing.sm) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(HelmColor.gaugeTrack.opacity(0.5))
                    Capsule()
                        .fill(HelmColor.accent)
                        .frame(width: max(6, geometry.size.width * elapsedFraction))
                        .animation(
                            reduceMotion ? nil : .linear(duration: 1),
                            value: elapsedFraction
                        )
                }
            }
            .frame(height: 6)

            Text(formattedTime(remainingSeconds))
                .helmType(.bigNumber, color: HelmColor.fg)
                .monospacedDigit()
                .frame(maxWidth: .infinity)

            HStack(spacing: HelmSpacing.sm) {
                if let onAdjust {
                    Button {
                        onAdjust(-15)
                    } label: {
                        Text("−15")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.helmSecondary)

                    Button {
                        onAdjust(15)
                    } label: {
                        Text("+15")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.helmSecondary)
                }

                Button("Skip", action: onSkip)
                    .buttonStyle(.helmPrimary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, HelmSpacing.md)
        .padding(.top, HelmSpacing.sm)
        .padding(.bottom, HelmSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(HelmColor.canvas)
    }

    private func formattedTime(_ remainingSeconds: Int) -> String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview("Rest timer banner") {
    RestTimerBanner(endsAt: Date().addingTimeInterval(140), totalSeconds: 150, onSkip: {}, onAdjust: { _ in })
        .helmTheme()
}
