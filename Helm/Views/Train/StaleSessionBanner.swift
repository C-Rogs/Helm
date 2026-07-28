import DesignSystem
import SwiftUI

struct StaleSessionBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .helmType(.body, color: HelmColor.fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HelmSpacing.md)
            .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.md)
                    .strokeBorder(HelmColor.depleted.opacity(0.35), lineWidth: 1)
            }
    }
}
