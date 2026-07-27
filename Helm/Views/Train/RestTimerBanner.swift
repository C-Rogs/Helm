import DesignSystem
import SwiftUI

struct RestTimerBanner: View {
    let endsAt: Date
    let onSkip: () -> Void
    var onAdjust: ((Int) -> Void)?
    var onRemainingSecondsChange: ((Int) -> Void)?

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
        HStack(spacing: HelmSpacing.sm) {
            if let onAdjust {
                Button("-15") { onAdjust(-15) }
                    .buttonStyle(.helmSecondary)
                    .font(.caption.monospacedDigit())
                    .frame(width: 44)
            }

            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("REST")
                    .helmType(.monoTag, color: HelmColor.fgSecondary)
                HelmNumericText(formattedTime(remainingSeconds))
                    .helmType(.bigNumber, color: HelmColor.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onAdjust {
                Button("+15") { onAdjust(15) }
                    .buttonStyle(.helmSecondary)
                    .font(.caption.monospacedDigit())
                    .frame(width: 44)
            }

            Button("Skip", action: onSkip)
                .buttonStyle(.helmSecondary)
                .frame(width: 72)
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.md)
                .strokeBorder(HelmColor.accent.opacity(0.35), lineWidth: 1)
        }
    }

    private func formattedTime(_ remainingSeconds: Int) -> String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview("Rest timer banner") {
    RestTimerBanner(endsAt: Date().addingTimeInterval(74), onSkip: {}, onAdjust: { _ in })
        .padding()
        .helmTheme()
}
