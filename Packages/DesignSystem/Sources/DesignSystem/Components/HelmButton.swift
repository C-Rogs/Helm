import SwiftUI

public struct HelmPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: .primary)
    }
}

public struct HelmSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: .secondary)
    }
}

private enum StyledKind {
    case primary
    case secondary
}

private struct StyledLabel: View {
    @Environment(\.helmReduceMotion) private var reduceMotion
    @Environment(\.helmSkin) private var skin
    @Environment(\.helmPalette) private var palette

    let configuration: ButtonStyleConfiguration
    let kind: StyledKind

    var body: some View {
        configuration.label
            .helmFont(.label)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, HelmSpacing.sm)
            .padding(.horizontal, HelmSpacing.md)
            .background(
                background.opacity(configuration.isPressed ? 0.85 : 1),
                in: RoundedRectangle(cornerRadius: HelmRadius.sm)
            )
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: HelmRadius.sm)
                        .strokeBorder(palette.hairline, lineWidth: 1)
                }
            }
            .helmPressChrome(
                isPressed: configuration.isPressed,
                scale: skin.pressScale,
                pressedOpacity: 1,
                reduceMotion: reduceMotion
            )
    }

    private var foreground: Color {
        switch kind {
        case .primary: palette.buttonPrimaryForeground
        case .secondary: palette.fg
        }
    }

    private var background: Color {
        switch kind {
        case .primary: palette.accentFill ?? palette.accent
        case .secondary: palette.surface
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
