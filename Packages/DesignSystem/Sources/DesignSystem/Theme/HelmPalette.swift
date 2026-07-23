import SwiftUI

public struct HelmPalette: Sendable, Equatable {
    public let canvas: Color
    public let surface: Color
    public let surfaceElevated: Color
    public let hairline: Color
    public let fg: Color
    public let fgSecondary: Color
    public let fgMuted: Color
    public let accent: Color
    public let accentFill: Color?
    public let depleted: Color
    public let compromised: Color
    public let ready: Color
    public let primed: Color
    public let chartGrid: Color
    public let chartLine: Color
    public let chartAreaFill: Color
    public let buttonPrimaryForeground: Color

    public func color(for state: HelmState) -> Color {
        switch state {
        case .depleted: depleted
        case .compromised: compromised
        case .ready: ready
        case .primed: primed
        }
    }

    public static let dark = HelmPalette(
        canvas: Color(hex: 0x000000),
        surface: Color(hex: 0x111112),
        surfaceElevated: Color(hex: 0x1C1C19),
        hairline: Color.white.opacity(0.09),
        fg: Color(hex: 0xF4F3EE),
        fgSecondary: Color(hex: 0xA8A7A0),
        fgMuted: Color(hex: 0x6B6A63),
        accent: Color(hex: 0xC6F24E),
        accentFill: nil,
        depleted: Color(hex: 0xFF6A4D),
        compromised: Color(hex: 0xFFB648),
        ready: Color(hex: 0xD7E85A),
        primed: Color(hex: 0xC6F24E),
        chartGrid: Color.white.opacity(0.06),
        chartLine: Color(hex: 0xC6F24E),
        chartAreaFill: Color(hex: 0xC6F24E).opacity(0.18),
        buttonPrimaryForeground: Color.black
    )

    public static let light = HelmPalette(
        canvas: Color(hex: 0xF4F2EC),
        surface: Color(hex: 0xE9E6DC),
        surfaceElevated: Color(hex: 0xFFFFFF),
        hairline: Color.black.opacity(0.14),
        fg: Color(hex: 0x16150F),
        fgSecondary: Color(hex: 0x57564D),
        fgMuted: Color(hex: 0x8A887E),
        accent: Color(hex: 0x4F6B00),
        accentFill: Color(hex: 0xC6F24E),
        depleted: Color(hex: 0xC24A2E),
        compromised: Color(hex: 0xB56B00),
        ready: Color(hex: 0x5F7A0A),
        primed: Color(hex: 0x4F6B00),
        chartGrid: Color.black.opacity(0.08),
        chartLine: Color(hex: 0x4F6B00),
        chartAreaFill: Color(hex: 0xC6F24E).opacity(0.35),
        buttonPrimaryForeground: Color(hex: 0x16150F)
    )
}

public enum HelmState: String, Sendable, CaseIterable {
    case depleted
    case compromised
    case ready
    case primed

    public static func readiness(score: Double) -> HelmState {
        switch score {
        case ..<40: .depleted
        case 40 ..< 55: .compromised
        case 55 ..< 75: .ready
        default: .primed
        }
    }

    /// Weekly hard-set volume relative to MEV/MRV landmarks.
    public static func volumeWeekly(sets: Double, mev: Int, mrv: Int) -> HelmState {
        if sets < Double(mev) { return .depleted }
        if sets > Double(mrv) { return .compromised }
        let midpoint = Double(mev + mrv) / 2
        if sets >= midpoint { return .primed }
        return .ready
    }

    /// Logged intake relative to calorie target (energy balance).
    public static func energyBalance(intakeKcal: Double, targetKcal: Double) -> HelmState {
        guard targetKcal > 0 else { return .compromised }
        let ratio = intakeKcal / targetKcal
        if ratio >= 0.95, ratio <= 1.05 { return .primed }
        if ratio < 0.7 { return .depleted }
        if ratio > 1.15 { return .compromised }
        return .ready
    }

    public var label: String {
        rawValue.uppercased()
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
