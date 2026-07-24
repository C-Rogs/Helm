import SwiftUI

public struct HelmPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HelmTypography.headline)
            .foregroundStyle(HelmColor.buttonPrimaryForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, HelmSpacing.sm)
            .padding(.horizontal, HelmSpacing.md)
            .background(
                HelmColor.buttonPrimaryBackground.opacity(configuration.isPressed ? 0.85 : 1),
                in: RoundedRectangle(cornerRadius: HelmRadius.sm)
            )
    }
}

public struct HelmSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HelmTypography.headline)
            .foregroundStyle(HelmColor.buttonSecondaryForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, HelmSpacing.sm)
            .padding(.horizontal, HelmSpacing.md)
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

public extension ButtonStyle where Self == HelmPrimaryButtonStyle {
    static var helmPrimary: HelmPrimaryButtonStyle { HelmPrimaryButtonStyle() }
}

public extension ButtonStyle where Self == HelmSecondaryButtonStyle {
    static var helmSecondary: HelmSecondaryButtonStyle { HelmSecondaryButtonStyle() }
}

public extension ButtonStyle where Self == HelmPressableButtonStyle {
    static var helmPressable: HelmPressableButtonStyle { HelmPressableButtonStyle() }
}

public extension ButtonStyle where Self == HelmPressableCardButtonStyle {
    static var helmPressableCard: HelmPressableCardButtonStyle { HelmPressableCardButtonStyle() }
}

#Preview("Buttons") {
    VStack(spacing: HelmSpacing.md) {
        Button("Ask Coach") {}
            .buttonStyle(.helmPrimary)
        Button("View history") {}
            .buttonStyle(.helmSecondary)
    }
    .padding()
    .helmTheme()
}
