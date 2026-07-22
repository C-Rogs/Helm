import Core
import DesignSystem
import SwiftUI

struct SetValueField: View {
    let title: String
    let value: String
    let placeholder: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: HelmSpacing.xxs) {
                Text(title)
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.textTertiary)
                Text(displayText)
                    .font(HelmTypography.statSmall)
                    .foregroundStyle(value.isEmpty ? HelmColor.textTertiary : HelmColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HelmSpacing.xs)
            .background(
                isActive ? HelmColor.accentMuted : HelmColor.surfaceElevated,
                in: RoundedRectangle(cornerRadius: HelmRadius.sm)
            )
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.sm)
                    .strokeBorder(isActive ? HelmColor.accent : HelmColor.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(displayText)")
    }

    private var displayText: String {
        value.isEmpty ? placeholder : value
    }
}

#Preview("Set value field") {
    HStack {
        SetValueField(title: "kg", value: "80", placeholder: "-", isActive: false, action: {})
        SetValueField(title: "reps", value: "", placeholder: "10", isActive: true, action: {})
    }
    .padding()
    .helmTheme()
}
