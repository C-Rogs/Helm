import SwiftUI
import UIKit

public enum HelmType {
    case heroNumber
    case bigNumber
    case number
    case title
    case label
    case body
    case monoTag

    public var font: Font {
        resolvedFont(prefersSystemFonts: HelmFontPreferences.prefersSystemFonts)
    }

    public func resolvedFont(prefersSystemFonts: Bool) -> Font {
        switch self {
        case .heroNumber:
            HelmFont.mono(size: 64, weight: .bold, prefersSystemFonts: prefersSystemFonts)
        case .bigNumber:
            HelmFont.mono(size: 26, weight: .bold, prefersSystemFonts: prefersSystemFonts)
        case .number:
            HelmFont.mono(size: 16, weight: .semibold, prefersSystemFonts: prefersSystemFonts)
        case .title:
            HelmFont.grotesk(size: 22, weight: .semibold, prefersSystemFonts: prefersSystemFonts)
        case .label:
            HelmFont.grotesk(size: 17, weight: .semibold, prefersSystemFonts: prefersSystemFonts)
        case .body:
            HelmFont.grotesk(size: 13.5, weight: .regular, prefersSystemFonts: prefersSystemFonts)
        case .monoTag:
            HelmFont.mono(size: 10.5, weight: .semibold, prefersSystemFonts: prefersSystemFonts)
        }
    }

    public var tracking: CGFloat? {
        switch self {
        case .monoTag: 1.68
        default: nil
        }
    }

    public var isUppercase: Bool {
        switch self {
        case .monoTag: true
        default: false
        }
    }
}

public enum HelmFontPreferences {
    /// Set by `HelmThemeCoordinator`; read by `HelmFont` resolvers.
    nonisolated(unsafe) public static var prefersSystemFonts = false
}

public enum HelmFont {
    public enum GroteskWeight {
        case regular
        case medium
        case semibold

        var postScriptName: String {
            switch self {
            case .regular: "SpaceGrotesk-Regular"
            case .medium: "SpaceGrotesk-Medium"
            case .semibold: "SpaceGrotesk-Bold"
            }
        }

        var systemWeight: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            }
        }
    }

    public enum MonoWeight {
        case semibold
        case bold

        var postScriptName: String {
            switch self {
            case .semibold: "JetBrainsMono-SemiBold"
            case .bold: "JetBrainsMono-Bold"
            }
        }

        var systemWeight: Font.Weight {
            switch self {
            case .semibold: .semibold
            case .bold: .bold
            }
        }
    }

    /// True when Core Text has a face for this PostScript name.
    public static func isRegistered(postScriptName: String) -> Bool {
        UIFont(name: postScriptName, size: 12) != nil
    }

    public static func grotesk(
        size: CGFloat,
        weight: GroteskWeight = .regular,
        prefersSystemFonts: Bool = HelmFontPreferences.prefersSystemFonts
    ) -> Font {
        if prefersSystemFonts {
            return .system(size: size, weight: weight.systemWeight)
        }
        return registeredOrSystem(
            postScriptName: weight.postScriptName,
            size: size,
            weight: weight.systemWeight
        )
    }

    public static func mono(
        size: CGFloat,
        weight: MonoWeight = .semibold,
        prefersSystemFonts: Bool = HelmFontPreferences.prefersSystemFonts
    ) -> Font {
        if prefersSystemFonts {
            // System default design + tabular digits (not JetBrains / SF Mono).
            return .system(size: size, weight: weight.systemWeight).monospacedDigit()
        }
        return registeredOrSystem(
            postScriptName: weight.postScriptName,
            size: size,
            weight: weight.systemWeight,
            monospacedDigit: true
        )
    }

    private static func registeredOrSystem(
        postScriptName: String,
        size: CGFloat,
        weight: Font.Weight,
        monospacedDigit: Bool = false
    ) -> Font {
        let font: Font
        if let uiFont = UIFont(name: postScriptName, size: size) {
            font = Font(uiFont)
        } else {
            font = .system(size: size, weight: weight)
        }
        return monospacedDigit ? font.monospacedDigit() : font
    }
}

/// Backward-compatible typography aliases used by M0.4 screens.
public enum HelmTypography {
    public static var displayLarge: Font { HelmType.heroNumber.font }
    public static var title: Font { HelmType.title.font }
    public static var headline: Font { HelmType.label.font }
    public static var body: Font { HelmType.body.font }
    public static var callout: Font { HelmFont.grotesk(size: 16, weight: .regular) }
    public static var caption: Font { HelmFont.grotesk(size: 13, weight: .regular) }
    public static var stat: Font { HelmType.bigNumber.font }
    public static var statSmall: Font { HelmFont.mono(size: 20, weight: .semibold) }
    public static var monoTag: Font { HelmType.monoTag.font }
}

public extension View {
    func helmType(_ style: HelmType, color: Color = HelmColor.fg) -> some View {
        modifier(HelmTypeModifier(style: style, color: color))
    }

    /// Font only (no color / tracking / uppercase). Prefer over `.font(HelmTypography.*)` so
    /// System font preference from the environment is observed and invalidates the view.
    func helmFont(_ style: HelmType) -> some View {
        modifier(HelmFontOnlyModifier(style: style))
    }
}

private struct HelmTypeModifier: ViewModifier {
    let style: HelmType
    let color: Color
    @Environment(\.helmPrefersSystemFonts) private var prefersSystemFonts
    @Environment(\.helmTypographyEpoch) private var typographyEpoch

    func body(content: Content) -> some View {
        HelmFontPreferences.prefersSystemFonts = prefersSystemFonts
        return content
            .font(resolvedFont)
            .foregroundStyle(color)
            .tracking(trackingValue)
            .textCase(style.isUppercase ? .uppercase : nil)
    }

    private var resolvedFont: Font {
        _ = typographyEpoch
        return style.resolvedFont(prefersSystemFonts: prefersSystemFonts)
    }

    private var trackingValue: CGFloat {
        if prefersSystemFonts { return 0 }
        return style.tracking ?? 0
    }
}

private struct HelmFontOnlyModifier: ViewModifier {
    let style: HelmType
    @Environment(\.helmPrefersSystemFonts) private var prefersSystemFonts
    @Environment(\.helmTypographyEpoch) private var typographyEpoch

    func body(content: Content) -> some View {
        HelmFontPreferences.prefersSystemFonts = prefersSystemFonts
        return content
            .font(resolvedFont)
    }

    private var resolvedFont: Font {
        _ = typographyEpoch
        return style.resolvedFont(prefersSystemFonts: prefersSystemFonts)
    }
}
