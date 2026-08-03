import DesignSystem
import SwiftUI

/// Compact ±15 chip: thumb-height, no equal-width stretch against Skip.
struct RestDockChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .helmFont(.label)
            .foregroundStyle(HelmColor.buttonSecondaryForeground)
            .padding(.horizontal, HelmSpacing.sm)
            .frame(minWidth: 52, minHeight: 44)
            .background(
                HelmColor.buttonSecondaryBackground.opacity(configuration.isPressed ? 0.85 : 1),
                in: RoundedRectangle(cornerRadius: HelmRadius.sm)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.sm)
                    .strokeBorder(HelmColor.buttonSecondaryBorder, lineWidth: 1)
            }
    }
}
