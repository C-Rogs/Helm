import DesignSystem
import SwiftUI

struct ProactiveCoachBanner: View {
    let message: String
    let onDismiss: () -> Void
    let onDiscuss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HStack {
                Text("Coach")
                    .helmType(.label, color: HelmColor.accent)
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.plain)
                    .helmType(.monoTag, color: HelmColor.fgSecondary)
            }

            Text(message)
                .helmType(.body, color: HelmColor.fg)

            Button("Discuss", action: onDiscuss)
                .buttonStyle(.helmSecondary)
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.md)
                .strokeBorder(HelmColor.accent.opacity(0.25), lineWidth: 1)
        }
    }
}
