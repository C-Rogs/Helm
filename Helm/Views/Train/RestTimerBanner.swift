import DesignSystem
import SwiftUI

struct RestTimerBanner: View {
    let remainingSeconds: Int
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: HelmSpacing.md) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text("REST")
                    .helmType(.monoTag, color: HelmColor.fgSecondary)
                Text(formattedTime)
                    .helmType(.bigNumber, color: HelmColor.accent)
            }
            Spacer()
            Button("Skip", action: onSkip)
                .buttonStyle(.helmSecondary)
                .frame(width: 88)
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.md)
                .strokeBorder(HelmColor.accent.opacity(0.35), lineWidth: 1)
        }
    }

    private var formattedTime: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview("Rest timer banner") {
    RestTimerBanner(remainingSeconds: 74, onSkip: {})
        .padding()
        .helmTheme()
}
