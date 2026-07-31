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
        let progress = progressFraction(remainingSeconds: remainingSeconds)

        HStack(spacing: HelmSpacing.xs) {
            if let onAdjust {
                adjustButton(systemImage: "minus", label: "Minus 15 seconds") {
                    onAdjust(-15)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("REST")
                    .helmType(.monoTag, color: HelmColor.fgSecondary)
                    .lineLimit(1)
                ZStack(alignment: .leading) {
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: HelmRadius.sm)
                            .fill(HelmColor.accent.opacity(0.18))
                            .frame(width: geometry.size.width * progress)
                            .animation(
                                reduceMotion ? nil : .linear(duration: 1),
                                value: progress
                            )
                    }
                    HelmNumericText(formattedTime(remainingSeconds))
                        .helmType(.number, color: HelmColor.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(height: 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if let onAdjust {
                adjustButton(systemImage: "plus", label: "Plus 15 seconds") {
                    onAdjust(15)
                }
            }

            Button("Skip", action: onSkip)
                .buttonStyle(.helmSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, HelmSpacing.sm)
        .padding(.vertical, HelmSpacing.xs)
        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.md)
                .strokeBorder(HelmColor.accent.opacity(0.35), lineWidth: 1)
        }
    }

    private func progressFraction(remainingSeconds: Int) -> CGFloat {
        let total = max(1, totalSeconds)
        return CGFloat(min(1, max(0, remainingSeconds))) / CGFloat(total)
    }

    private func adjustButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.helmSecondary)
        .accessibilityLabel(label)
    }

    private func formattedTime(_ remainingSeconds: Int) -> String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview("Rest timer banner") {
    RestTimerBanner(endsAt: Date().addingTimeInterval(74), totalSeconds: 90, onSkip: {}, onAdjust: { _ in })
        .padding()
        .helmTheme()
}
