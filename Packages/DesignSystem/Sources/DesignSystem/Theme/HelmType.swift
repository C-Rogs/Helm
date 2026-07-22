import SwiftUI

public enum HelmType {
    case heroNumber
    case bigNumber
    case number
    case title
    case label
    case body
    case monoTag

    public var font: Font {
        switch self {
        case .heroNumber:
            HelmFont.mono(size: 64, weight: .bold)
        case .bigNumber:
            HelmFont.mono(size: 26, weight: .bold)
        case .number:
            HelmFont.mono(size: 16, weight: .semibold)
        case .title:
            HelmFont.grotesk(size: 22, weight: .semibold)
        case .label:
            HelmFont.grotesk(size: 17, weight: .semibold)
        case .body:
            HelmFont.grotesk(size: 13.5, weight: .regular)
        case .monoTag:
            HelmFont.mono(size: 10.5, weight: .semibold)
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
    }

    public static func grotesk(size: CGFloat, weight: GroteskWeight = .regular) -> Font {
        .custom(weight.postScriptName, size: size)
    }

    public static func mono(size: CGFloat, weight: MonoWeight = .semibold) -> Font {
        .custom(weight.postScriptName, size: size).monospacedDigit()
    }
}

/// Backward-compatible typography aliases used by M0.4 screens.
public enum HelmTypography {
    public static let displayLarge = HelmType.heroNumber.font
    public static let title = HelmType.title.font
    public static let headline = HelmType.label.font
    public static let body = HelmType.body.font
    public static let callout = HelmFont.grotesk(size: 16, weight: .regular)
    public static let caption = HelmFont.grotesk(size: 13, weight: .regular)
    public static let stat = HelmType.bigNumber.font
    public static let statSmall = HelmFont.mono(size: 20, weight: .semibold)
    public static let monoTag = HelmType.monoTag.font
}

public extension View {
    func helmType(_ style: HelmType, color: Color = HelmColor.fg) -> some View {
        modifier(HelmTypeModifier(style: style, color: color))
    }
}

private struct HelmTypeModifier: ViewModifier {
    let style: HelmType
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(style.font)
            .foregroundStyle(color)
            .tracking(style.tracking ?? 0)
            .textCase(style.isUppercase ? .uppercase : nil)
    }
}
