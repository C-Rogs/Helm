import SwiftUI

/// Single source of truth for Helm colours. No other file may define raw colours.
public enum HelmColor {
    private static var palette: HelmPalette { HelmActivePalette.current }

    public static var canvas: Color { palette.canvas }
    public static var background: Color { palette.canvas }
    public static var surface: Color { palette.surface }
    public static var surfaceElevated: Color { palette.surfaceElevated }
    public static var hairline: Color { palette.hairline }
    public static var border: Color { palette.hairline }
    public static var surfaceEngineTag: Color { palette.surfaceEngineTag }
    public static var scrim: Color { palette.scrim }

    public static var fg: Color { palette.fg }
    public static var textPrimary: Color { palette.fg }
    public static var fgSecondary: Color { palette.fgSecondary }
    public static var textSecondary: Color { palette.fgSecondary }
    public static var fgMuted: Color { palette.fgMuted }
    public static var textTertiary: Color { palette.fgMuted }

    public static var accent: Color { palette.accent }
    public static var accentFill: Color { palette.accentFill ?? palette.accent }
    public static var accentMuted: Color { palette.accent.opacity(0.35) }

    public static var depleted: Color { palette.depleted }
    public static var compromised: Color { palette.compromised }
    public static var ready: Color { palette.ready }
    public static var primed: Color { palette.primed }
    public static var positive: Color { palette.primed }
    public static var warning: Color { palette.compromised }
    public static var destructive: Color { palette.depleted }

    public static var gaugeTrack: Color { palette.hairline }
    public static var gaugeFillStart: Color { palette.accent }
    public static var gaugeFillEnd: Color { palette.primed }

    public static var chartGrid: Color { palette.chartGrid }
    public static var chartLine: Color { palette.chartLine }
    public static var chartAreaFill: Color { palette.chartAreaFill }

    public static var buttonPrimaryBackground: Color { palette.accentFill ?? palette.accent }
    public static var buttonPrimaryForeground: Color { palette.buttonPrimaryForeground }
    public static var buttonSecondaryBackground: Color { palette.surfaceElevated }
    public static var buttonSecondaryForeground: Color { palette.fg }
    public static var buttonSecondaryBorder: Color { palette.hairline }

    public static func color(for state: HelmState) -> Color {
        palette.color(for: state)
    }
}

enum HelmActivePalette {
    nonisolated(unsafe) static var current: HelmPalette = .dark
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
    public static let emptyChartMinHeight: CGFloat = HelmSpacing.sm * 10
    public static let progressTrackHeight: CGFloat = HelmSpacing.xs - 2
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
