import DesignSystem
import SwiftUI

@MainActor
@ViewBuilder
func chartHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
        Text(title)
            .helmType(.title)
        Text(subtitle)
            .helmType(.body, color: HelmColor.fgSecondary)
    }
}

@MainActor
func emptyChartCopy(_ message: String) -> some View {
    Text(message)
        .helmType(.body, color: HelmColor.fgMuted)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
}
