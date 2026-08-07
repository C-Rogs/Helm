import Core
import SwiftUI

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Watch theme – mirrors DesignSystem dark palette + type scale
// but self-contained so the watch target does not pull in
// Diagnostics, UIKit, CoreHaptics, or font resources.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

// MARK: - Palette (dark-only; watch is OLED)

enum WatchPalette {
    static let canvas        = Color(hex: 0x000000)   // OLED true black
    static let surface       = Color(hex: 0x111112)   // cards
    static let surfaceElevated = Color(hex: 0x1C1C19) // rows, inputs
    static let hairline      = Color.white.opacity(0.09)
    static let fg            = Color(hex: 0xF4F3EE)   // primary text
    static let fgSecondary   = Color(hex: 0xA8A7A0)   // body, labels
    static let fgMuted       = Color(hex: 0x6B6A63)   // units, captions

    // Accent: lime default (matches HelmAccentPreset.lime dark)
    static let accent        = Color(hex: 0xC6F24E)
    static let accentFill    = Color(hex: 0xC6F24E)
    static let buttonPrimaryForeground = Color.black

    // State ramp
    static let depleted       = Color(hex: 0xFF6A4D)
    static let compromised    = Color(hex: 0xFFB648)
    static let ready          = Color(hex: 0xD7E85A)
    static let primed         = Color(hex: 0xC6F24E)
}

// MARK: - Type scale (watch-adjusted)

enum WatchType {
    /// Large hero number (ARC score, HR)
    case heroNumber
    /// Card metric readouts
    case bigNumber
    /// Inline values
    case number
    /// Screen / section titles
    case title
    /// List primary text
    case label
    /// Body / descriptions
    case body
    /// Section eyebrows, unit labels
    case monoTag

    var font: Font {
        switch self {
        case .heroNumber: .system(size: 36, weight: .bold, design: .rounded).monospacedDigit()
        case .bigNumber:  .system(size: 22, weight: .bold).monospacedDigit()
        case .number:     .system(size: 15, weight: .semibold).monospacedDigit()
        case .title:      .system(size: 17, weight: .semibold)
        case .label:      .system(size: 15, weight: .semibold)
        case .body:       .system(size: 13, weight: .regular)
        case .monoTag:    .system(size: 10, weight: .medium, design: .monospaced)
        }
    }
}

// MARK: - Zone color (single source)

enum WatchZoneColor {
    static func color(for zone: HeartRateZone?) -> Color {
        switch zone {
        case .zone1: .mint
        case .zone2: .blue
        case .zone3: .yellow
        case .zone4: .orange
        case .zone5: .red
        case nil: WatchPalette.fgSecondary
        }
    }
}

// MARK: - Readiness band color

enum WatchReadinessBand {
    static func color(for score: Int) -> Color {
        switch score {
        case ..<40:  WatchPalette.depleted
        case 40..<55: WatchPalette.compromised
        case 55..<75: WatchPalette.ready
        default:      WatchPalette.primed
        }
    }
}

// MARK: - View modifiers

extension View {
    /// Apply Helm watch theme: OLED-black background, accent tint, system fonts.
    func helmWatchTheme() -> some View {
        self
            .tint(WatchPalette.accent)
            .background(WatchPalette.canvas)
            .preferredColorScheme(.dark)
    }

    /// Standard screen background for watch content areas.
    func helmWatchScreenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(WatchPalette.canvas.ignoresSafeArea())
    }
}

// MARK: - Color extension (hex init, shared with watch)

private extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red   = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >>  8) & 0xFF) / 255
        let blue  = Double(hex        & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
