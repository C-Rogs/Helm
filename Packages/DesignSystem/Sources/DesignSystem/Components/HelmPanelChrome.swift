import SwiftUI

/// Elevated panel chrome (banners, note fields, option tiles) that follows `HelmSkin`.
public struct HelmPanelChromeModifier: ViewModifier {
    public enum Emphasis {
        case surface
        case elevated
        /// Rounded accent wash. Matches `AdjustmentBanner` on every skin, including Signal.
        case accentQuiet
    }

    @Environment(\.helmSkin) private var skin
    @Environment(\.helmPalette) private var palette
    @Environment(\.helmTypographyEpoch) private var typographyEpoch

    private let emphasis: Emphasis
    private let cornerRadius: CGFloat
    private let isLive: Bool

    public init(
        emphasis: Emphasis = .elevated,
        cornerRadius: CGFloat = HelmRadius.md,
        isLive: Bool = false
    ) {
        self.emphasis = emphasis
        self.cornerRadius = cornerRadius
        self.isLive = isLive
    }

    public func body(content: Content) -> some View {
        let _ = typographyEpoch
        if isAccentQuiet {
            content
                .background(
                    palette.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: accentQuietRadius)
                )
                .overlay {
                    HelmBrushedAccentRim(
                        shape: RoundedRectangle(cornerRadius: accentQuietRadius),
                        isLive: isLive
                    )
                }
        } else {
            skinnedChrome(content)
        }
    }

    @ViewBuilder
    private func skinnedChrome(_ content: Content) -> some View {
        switch skin {
        case .signal:
            content
                .background {
                    Rectangle()
                        .fill(SignalChrome.panelFill(palette: palette))
                }
                .overlay {
                    SignalHUDFrame(emphasized: false)
                }
                .shadow(
                    color: SignalChrome.glow(palette: palette, intensity: 0.16),
                    radius: 5,
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

    private var isAccentQuiet: Bool { emphasis == .accentQuiet }

    private var accentQuietRadius: CGFloat { HelmRadius.card }

    private var fillColor: Color {
        switch emphasis {
        case .surface: palette.surface
        case .elevated: palette.surfaceElevated
        case .accentQuiet: palette.accent.opacity(0.12)
        }
    }

    private var strokeColor: Color {
        switch emphasis {
        case .surface, .elevated: palette.hairline
        case .accentQuiet: palette.accent.opacity(0.35)
        }
    }
}

/// Brushed accent rim: one hue, specular tick, tight bloom. Traveling catch-light stands in for AI sparkle.
public struct HelmBrushedAccentRim<S: Shape>: View {
    private let shape: S
    private let isLive: Bool

    @Environment(\.helmPalette) private var palette
    @Environment(\.helmReduceMotion) private var reduceMotion

    public init(shape: S, isLive: Bool = false) {
        self.shape = shape
        self.isLive = isLive
    }

    public var body: some View {
        if reduceMotion {
            rim(angle: 0, glowOpacity: 0.16)
        } else {
            TimelineView(.animation) { context in
                let period = isLive ? 4.2 : 12.0
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = t.truncatingRemainder(dividingBy: period) / period
                let glow: Double = {
                    guard isLive else { return 0.2 }
                    return 0.18 + 0.2 * (0.5 + 0.5 * sin(phase * 2 * .pi))
                }()
                rim(angle: phase * 360, glowOpacity: glow)
            }
        }
    }

    private func rim(angle: Double, glowOpacity: Double) -> some View {
        let bright = palette.accentFill ?? palette.accent
        return ZStack {
            shape
                .stroke(bright.opacity(glowOpacity), lineWidth: 4)
                .blur(radius: 4)
            shape
                .stroke(metalGradient(angle: angle), lineWidth: 1.25)
        }
        .allowsHitTesting(false)
    }

    private func metalGradient(angle: Double) -> AngularGradient {
        let bright = palette.accentFill ?? palette.accent
        return AngularGradient(
            colors: [
                bright,
                palette.accent.opacity(0.35),
                palette.fg.opacity(0.55),
                bright.opacity(0.8),
                palette.accent.opacity(0.28),
                bright
            ],
            center: .center,
            angle: .degrees(angle)
        )
    }
}

public extension View {
    func helmPanelChrome(
        _ emphasis: HelmPanelChromeModifier.Emphasis = .elevated,
        cornerRadius: CGFloat = HelmRadius.md,
        isLive: Bool = false
    ) -> some View {
        modifier(
            HelmPanelChromeModifier(
                emphasis: emphasis,
                cornerRadius: cornerRadius,
                isLive: isLive
            )
        )
    }
}
