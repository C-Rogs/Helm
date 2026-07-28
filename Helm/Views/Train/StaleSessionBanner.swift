import DesignSystem
import SwiftUI

struct StaleSessionBanner: View {
    let message: String
    let onDiscuss: () -> Void
    let onRegenerate: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text(message)
                .helmType(.body, color: HelmColor.fg)

            HStack(spacing: HelmSpacing.sm) {
                Button("Discuss", action: onDiscuss)
                    .buttonStyle(.helmSecondary)
                Button("Regenerate", action: onRegenerate)
                    .buttonStyle(.helmPrimary)
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.helmSecondary)
            }
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.md)
                .strokeBorder(HelmColor.depleted.opacity(0.35), lineWidth: 1)
        }
    }
}
