import SwiftUI

/// Elevated panel chrome (banners, note fields, option tiles) that follows `HelmSkin`.
public struct HelmPanelChromeModifier: ViewModifier {
    public enum Emphasis {
        case surface
        case elevated
        case accentQuiet
    }

    @Environment(\.helmSkin) private var skin
    @Environment(\.helmPalette) private var palette

    private let emphasis: Emphasis
    private let cornerRadius: CGFloat

    public init(emphasis: Emphasis = .elevated, cornerRadius: CGFloat = HelmRadius.md) {
        self.emphasis = emphasis
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        switch skin {
        case .signal:
            content
                .background {
                    Rectangle()
                        .fill(SignalChrome.panelFill(palette: palette))
                }
                .overlay {
                    SignalHUDFrame(emphasized: emphasis == .accentQuiet)
                }
                .shadow(
                    color: SignalChrome.glow(
                        palette: palette,
                        intensity: emphasis == .accentQuiet ? 0.32 : 0.16
                    ),
                    radius: emphasis == .accentQuiet ? 8 : 5,
                    y: 0
                )
        case .dataSheet:
            content
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(strokeColor)
                        .frame(height: 1)
                }
        case .instrument, .stateField, .blueprint:
            content
                .background(fillColor, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(strokeColor, lineWidth: 1)
                }
        }
    }

    private var fillColor: Color {
        switch emphasis {
        case .surface: palette.surface
        case .elevated: palette.surfaceElevated
        case .accentQuiet: palette.accent.opacity(0.08)
        }
    }

    private var strokeColor: Color {
        switch emphasis {
        case .surface, .elevated: palette.hairline
        case .accentQuiet: palette.accent.opacity(0.25)
        }
    }
}

public extension View {
    func helmPanelChrome(
        _ emphasis: HelmPanelChromeModifier.Emphasis = .elevated,
        cornerRadius: CGFloat = HelmRadius.md
    ) -> some View {
        modifier(HelmPanelChromeModifier(emphasis: emphasis, cornerRadius: cornerRadius))
    }
}
