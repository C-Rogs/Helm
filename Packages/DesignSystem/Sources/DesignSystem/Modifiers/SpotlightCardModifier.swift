import SwiftUI

/// Elevates the active logging card and dims siblings when Focus Mode is on.
public struct SpotlightCardModifier: ViewModifier {
    public let isFocused: Bool
    public let isFocusModeEnabled: Bool

    @Environment(\.helmReduceMotion) private var reduceMotion
    @Environment(\.helmPalette) private var palette

    public init(isFocused: Bool, isFocusModeEnabled: Bool) {
        self.isFocused = isFocused
        self.isFocusModeEnabled = isFocusModeEnabled
    }

    private var shouldDim: Bool {
        isFocusModeEnabled && !isFocused
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .blur(radius: blurRadius)
            .zIndex(isFocused ? 1 : 0)
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                y: shadowY
            )
            .animation(
                HelmMotion.animation(
                    .spring(response: 0.4, dampingFraction: 0.7),
                    reduceMotion: reduceMotion
                ),
                value: isFocused
            )
            .animation(
                HelmMotion.animation(
                    .spring(response: 0.4, dampingFraction: 0.7),
                    reduceMotion: reduceMotion
                ),
                value: isFocusModeEnabled
            )
    }

    private var scale: CGFloat {
        if reduceMotion { return 1.0 }
        return shouldDim ? 0.95 : 1.0
    }

    private var opacity: Double {
        shouldDim ? 0.4 : 1.0
    }

    private var blurRadius: CGFloat {
        if reduceMotion { return 0 }
        return shouldDim ? 2.0 : 0
    }

    private var shadowColor: Color {
        guard isFocused, isFocusModeEnabled else { return .clear }
        return palette.fg.opacity(0.18)
    }

    private var shadowRadius: CGFloat {
        guard isFocused, isFocusModeEnabled else { return 0 }
        return reduceMotion ? 4 : 10
    }

    private var shadowY: CGFloat {
        guard isFocused, isFocusModeEnabled else { return 0 }
        return 4
    }
}

public extension View {
    func spotlightEffect(isFocused: Bool, isFocusModeEnabled: Bool) -> some View {
        modifier(
            SpotlightCardModifier(
                isFocused: isFocused,
                isFocusModeEnabled: isFocusModeEnabled
            )
        )
    }
}
