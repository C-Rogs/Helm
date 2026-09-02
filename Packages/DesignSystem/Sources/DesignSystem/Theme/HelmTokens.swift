import SwiftUI
import UIKit

/// Single source of truth for Helm colours. No other file may define raw colours.
///
/// Tokens wrap `UIColor` trait callbacks so Light/Dark flips (including
/// `overrideUserInterfaceStyle`) re-resolve without a process restart.
public enum HelmColor {
    private static func token(_ pick: @escaping @Sendable (HelmPalette) -> Color) -> Color {
        Color(uiColor: UIColor { traits in
            let appearance: HelmPaletteAppearance
            switch traits.userInterfaceStyle {
            case .light: appearance = .light
            case .dark: appearance = .dark
            default:
                appearance = HelmActivePalette.appearance
            }
            let palette = HelmPalette.resolved(
                appearance: appearance,
                accent: HelmActivePalette.accentSource
            )
            return UIColor(pick(palette))
        })
    }

    public static var canvas: Color { token(\.canvas) }
    public static var background: Color { token(\.canvas) }
    public static var surface: Color { token(\.surface) }
    public static var surfaceElevated: Color { token(\.surfaceElevated) }
    public static var hairline: Color { token(\.hairline) }
    public static var border: Color { token(\.hairline) }
    public static var surfaceEngineTag: Color { token(\.surfaceEngineTag) }
    public static var scrim: Color { token(\.scrim) }

    public static var fg: Color { token(\.fg) }
    public static var textPrimary: Color { token(\.fg) }
    public static var fgSecondary: Color { token(\.fgSecondary) }
    public static var textSecondary: Color { token(\.fgSecondary) }
    public static var fgMuted: Color { token(\.fgMuted) }
    public static var textTertiary: Color { token(\.fgMuted) }

    public static var accent: Color { token(\.accent) }
    public static var accentFill: Color { token { $0.accentFill ?? $0.accent } }
    public static var accentMuted: Color { accent.opacity(0.35) }

    public static var depleted: Color { token(\.depleted) }
    public static var compromised: Color { token(\.compromised) }
    public static var ready: Color { token(\.ready) }
    public static var primed: Color { token(\.primed) }
    public static var positive: Color { token(\.primed) }
    public static var warning: Color { token(\.compromised) }
    public static var destructive: Color { token(\.depleted) }

    public static var gaugeTrack: Color { token(\.hairline) }
    public static var gaugeFillStart: Color { token(\.accent) }
    public static var gaugeFillEnd: Color { token(\.primed) }

    public static var chartGrid: Color { token(\.chartGrid) }
    public static var chartLine: Color { token(\.chartLine) }
    public static var chartAreaFill: Color { token(\.chartAreaFill) }

    public static var buttonPrimaryBackground: Color { token { $0.accentFill ?? $0.accent } }
    public static var buttonPrimaryForeground: Color { token(\.buttonPrimaryForeground) }
    public static var buttonSecondaryBackground: Color { token(\.surface) }
    public static var buttonSecondaryForeground: Color { token(\.fg) }
    public static var buttonSecondaryBorder: Color { token(\.hairline) }

    public static func color(for state: HelmState) -> Color {
        switch state {
        case .depleted: depleted
        case .compromised: compromised
        case .ready: ready
        case .primed: primed
        }
    }
}

enum HelmActivePalette {
    nonisolated(unsafe) static var current: HelmPalette = .dark
    nonisolated(unsafe) static var accentSource: HelmAccentSource = .default
    nonisolated(unsafe) static var appearance: HelmPaletteAppearance = .dark
}

public enum HelmSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 22
    public static let xl: CGFloat = 32
    public static let screenGutter: CGFloat = 22
}

public enum HelmRadius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let card: CGFloat = 18
    public static let lg: CGFloat = 20
    public static let gauge: CGFloat = 14
}

public enum HelmLayout {
    /// Apple HIG minimum touch target.
    public static let minTapTarget: CGFloat = 44
    public static let chartHeight: CGFloat = HelmSpacing.sm * 15
    public static let exerciseHistoryImageHeight: CGFloat = HelmSpacing.xl * 5
    public static let emptyChartMinHeight: CGFloat = HelmSpacing.sm * 10
    public static let progressTrackHeight: CGFloat = HelmSpacing.xs - 2
    /// Volume track; logged overlay sits inset so the projected pill stays one shape.
    public static let landmarkVolumeTrackHeight: CGFloat = HelmSpacing.lg
    public static let landmarkVolumeScaleHeight: CGFloat = HelmSpacing.md
    public static let arcReadoutMaxWidth: CGFloat = HelmSpacing.lg * 10
    public static let trainScrollBottomInset: CGFloat = HelmSpacing.lg * 5
    public static let numpadHeight: CGFloat = HelmNumpadMetrics.preferredHeight
    public static let trainScrollBottomInsetWithNumpad: CGFloat = numpadHeight + HelmSpacing.xl
    public static let trainRPEWheelRowHeight: CGFloat = 44
    public static let trainRPEWheelVisibleRows: CGFloat = 3
    public static let trainRPEWheelHeight: CGFloat = trainRPEWheelRowHeight * trainRPEWheelVisibleRows
    /// Dismiss chip + wheel + Done button clearance for RPE overlay.
    public static let trainScrollBottomInsetWithRPE: CGFloat =
        trainRPEWheelHeight + HelmSpacing.xl * 2 + HelmSpacing.sm * 4 + trainRPEWheelRowHeight
    /// Soft fade into bottom session chrome. Keep short so exercise list stays readable.
    /// Extra scroll clearance for compact rest dock (progress + timer row + optional up-next).
    public static let trainRestBannerScrollInset: CGFloat = HelmSpacing.xl * 3
    public static let compactArcWidth: CGFloat = HelmSpacing.sm * 10
    public static let compactEnergyArcWidth: CGFloat = HelmSpacing.md * 6
    public static let calorieArcMaxWidth: CGFloat = HelmSpacing.lg * 12
}
