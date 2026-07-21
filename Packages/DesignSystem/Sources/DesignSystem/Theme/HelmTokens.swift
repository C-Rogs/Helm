import SwiftUI

/// Single source of truth for Helm colours. No other file may define raw colours.
public enum HelmColor {
    public static let background = Color.black
    public static let surface = Color(red: 0.11, green: 0.11, blue: 0.12)
    public static let surfaceElevated = Color(red: 0.17, green: 0.17, blue: 0.18)
    public static let border = Color.white.opacity(0.08)

    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 0.56, green: 0.56, blue: 0.58)
    public static let textTertiary = Color(red: 0.39, green: 0.39, blue: 0.40)

    public static let accent = Color(red: 0.20, green: 0.78, blue: 0.85)
    public static let accentMuted = Color(red: 0.20, green: 0.78, blue: 0.85).opacity(0.35)
    public static let positive = Color(red: 0.30, green: 0.85, blue: 0.55)
    public static let warning = Color(red: 0.98, green: 0.73, blue: 0.25)
    public static let destructive = Color(red: 0.96, green: 0.33, blue: 0.33)

    public static let gaugeTrack = Color(red: 0.22, green: 0.22, blue: 0.24)
    public static let gaugeFillStart = accent
    public static let gaugeFillEnd = positive

    public static let chartGrid = Color.white.opacity(0.06)
    public static let chartLine = accent
    public static let chartAreaFill = accent.opacity(0.18)

    public static let buttonPrimaryBackground = accent
    public static let buttonPrimaryForeground = Color.black
    public static let buttonSecondaryBackground = surfaceElevated
    public static let buttonSecondaryForeground = textPrimary
    public static let buttonSecondaryBorder = border
}

public enum HelmTypography {
    public static let displayLarge = Font.system(size: 48, weight: .bold, design: .rounded)
    public static let title = Font.system(size: 22, weight: .semibold, design: .default)
    public static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    public static let body = Font.system(size: 17, weight: .regular, design: .default)
    public static let callout = Font.system(size: 16, weight: .regular, design: .default)
    public static let caption = Font.system(size: 13, weight: .regular, design: .default)
    public static let stat = Font.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
    public static let statSmall = Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
}

public enum HelmSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 24
    public static let xl: CGFloat = 32
}

public enum HelmRadius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let gauge: CGFloat = 14
}
