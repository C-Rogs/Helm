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

    /// Lime dark profile (default accent). Kept as a named static for call sites and parity tests.
    public static let dark = resolved(appearance: .dark, accent: .default)

    /// Lime light profile (default accent). Kept as a named static for call sites and parity tests.
    public static let light = resolved(appearance: .light, accent: .default)

    public static func resolved(
        appearance: HelmPaletteAppearance,
        accent: HelmAccentSource
    ) -> HelmPalette {
        let neutrals = appearance.neutrals
        let accentTokens = AccentTokenSet.resolve(source: accent, appearance: appearance)
        return HelmPalette(
            canvas: neutrals.canvas,
            surface: neutrals.surface,
            surfaceElevated: neutrals.surfaceElevated,
            hairline: neutrals.hairline,
            fg: neutrals.fg,
            fgSecondary: neutrals.fgSecondary,
            fgMuted: neutrals.fgMuted,
            accent: accentTokens.accent,
            accentFill: accentTokens.accentFill,
            depleted: neutrals.depleted,
            compromised: neutrals.compromised,
            ready: accentTokens.ready,
            primed: accentTokens.primed,
            chartGrid: neutrals.chartGrid,
            chartLine: accentTokens.chartLine,
            chartAreaFill: accentTokens.chartAreaFill,
            buttonPrimaryForeground: accentTokens.buttonPrimaryForeground
        )
    }
}

public enum HelmPaletteAppearance: Sendable, Equatable {
    case dark
    case light

    fileprivate var neutrals: NeutralTokenSet {
        switch self {
        case .dark:
            NeutralTokenSet(
                canvas: Color(hex: 0x000000),
                surface: Color(hex: 0x111112),
                surfaceElevated: Color(hex: 0x1C1C19),
                hairline: Color.white.opacity(0.09),
                fg: Color(hex: 0xF4F3EE),
                fgSecondary: Color(hex: 0xA8A7A0),
                fgMuted: Color(hex: 0x6B6A63),
                depleted: Color(hex: 0xFF6A4D),
                compromised: Color(hex: 0xFFB648),
                chartGrid: Color.white.opacity(0.06)
            )
        case .light:
            NeutralTokenSet(
                canvas: Color(hex: 0xF2F2F7),
                surface: Color(hex: 0xFFFFFF),
                surfaceElevated: Color(hex: 0xFFFFFF),
                hairline: Color.black.opacity(0.14),
                fg: Color(hex: 0x16150F),
                fgSecondary: Color(hex: 0x57564D),
                fgMuted: Color(hex: 0x8A887E),
                depleted: Color(hex: 0xC24A2E),
                compromised: Color(hex: 0xB56B00),
                chartGrid: Color.black.opacity(0.08)
            )
        }
    }
}

/// Named accent recipes. Reserved for future accent additions.
public enum HelmAccentPreset: String, Sendable, CaseIterable, Identifiable {
    case lime

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .lime: "Lime"
        }
    }

    /// Bright dark-profile accent for Settings swatches.
    public var swatchHex: UInt32 {
        switch self {
        case .lime: 0xC6F24E
        }
    }

    public var swatchColor: Color {
        Color(hex: swatchHex)
    }
}

/// Accent input for palette resolution. Presets ship now; `.custom` is reserved for a later picker.
public enum HelmAccentSource: Sendable, Equatable {
    case preset(HelmAccentPreset)
    case custom(baseHex: UInt32)

    public static let `default`: HelmAccentSource = .preset(.lime)

    public var selectablePreset: HelmAccentPreset? {
        switch self {
        case .preset(let preset): preset
        case .custom: nil
        }
    }

    public var persistenceToken: String {
        switch self {
        case .preset(let preset):
            "preset:\(preset.rawValue)"
        case .custom(let hex):
            String(format: "custom:%06X", hex)
        }
    }

    public static func fromPersistence(_ token: String?) -> HelmAccentSource {
        guard let token, !token.isEmpty else { return .default }
        if token.hasPrefix("preset:") {
            let raw = String(token.dropFirst("preset:".count))
            if let preset = HelmAccentPreset(rawValue: raw) {
                return .preset(preset)
            }
            return .default
        }
        if token.hasPrefix("custom:") {
            let raw = String(token.dropFirst("custom:".count))
            if let hex = UInt32(raw, radix: 16) {
                return .custom(baseHex: hex)
            }
            return .default
        }
        // Legacy: bare preset raw value
        if let preset = HelmAccentPreset(rawValue: token) {
            return .preset(preset)
        }
        return .default
    }
}

private struct NeutralTokenSet {
    let canvas: Color
    let surface: Color
    let surfaceElevated: Color
    let hairline: Color
    let fg: Color
    let fgSecondary: Color
    let fgMuted: Color
    let depleted: Color
    let compromised: Color
    let chartGrid: Color
}

private struct AccentTokenSet {
    let accent: Color
    let accentFill: Color?
    let ready: Color
    let primed: Color
    let chartLine: Color
    let chartAreaFill: Color
    let buttonPrimaryForeground: Color

    static func resolve(source: HelmAccentSource, appearance: HelmPaletteAppearance) -> AccentTokenSet {
        switch source {
        case .preset(let preset):
            presetTokens(preset, appearance: appearance)
        case .custom(let baseHex):
            customTokens(baseHex: baseHex, appearance: appearance)
        }
    }

    private static func presetTokens(
        _ preset: HelmAccentPreset,
        appearance: HelmPaletteAppearance
    ) -> AccentTokenSet {
        switch (preset, appearance) {
        case (.lime, .dark):
            AccentTokenSet(
                accent: Color(hex: 0xC6F24E),
                accentFill: nil,
                ready: Color(hex: 0xD7E85A),
                primed: Color(hex: 0xC6F24E),
                chartLine: Color(hex: 0xC6F24E),
                chartAreaFill: Color(hex: 0xC6F24E).opacity(0.18),
                buttonPrimaryForeground: Color.black
            )
        case (.lime, .light):
            AccentTokenSet(
                accent: Color(hex: 0x4F6B00),
                accentFill: Color(hex: 0xC6F24E),
                ready: Color(hex: 0x5F7A0A),
                primed: Color(hex: 0x4F6B00),
                chartLine: Color(hex: 0x4F6B00),
                chartAreaFill: Color(hex: 0xC6F24E).opacity(0.35),
                buttonPrimaryForeground: Color(hex: 0x16150F)
            )
        }
    }

    /// Reserved for a future colour picker. Dark uses the hex bright; light darkens for text AA.
    private static func customTokens(baseHex: UInt32, appearance: HelmPaletteAppearance) -> AccentTokenSet {
        let bright = Color(hex: baseHex)
        switch appearance {
        case .dark:
            return AccentTokenSet(
                accent: bright,
                accentFill: nil,
                ready: bright.opacity(0.85),
                primed: bright,
                chartLine: bright,
                chartAreaFill: bright.opacity(0.18),
                buttonPrimaryForeground: Color.black
            )
        case .light:
            let textAccent = Color(hex: darkenForLightText(baseHex))
            return AccentTokenSet(
                accent: textAccent,
                accentFill: bright,
                ready: textAccent,
                primed: textAccent,
                chartLine: textAccent,
                chartAreaFill: bright.opacity(0.35),
                buttonPrimaryForeground: Color(hex: 0x16150F)
            )
        }
    }

    /// Rough AA-oriented darkening toward ink for light canvas text accents.
    private static func darkenForLightText(_ hex: UInt32) -> UInt32 {
        let r = Double((hex >> 16) & 0xFF)
        let g = Double((hex >> 8) & 0xFF)
        let b = Double(hex & 0xFF)
        let factor = 0.28
        let nr = UInt32(min(255, max(0, r * factor)))
        let ng = UInt32(min(255, max(0, g * factor)))
        let nb = UInt32(min(255, max(0, b * factor)))
        return (nr << 16) | (ng << 8) | nb
    }
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

    /// Weekly hard-set volume relative to MEV/MRV landmarks (fill color only).
    /// Do not use `label` on volume rows; use `VolumeLandmarkStatus` instead.
    public static func volumeWeekly(sets: Double, mev: Int, mrv: Int) -> HelmState {
        switch VolumeLandmarkStatus.resolve(sets: sets, mev: mev, mrv: mrv) {
        case .belowMEV:
            return .depleted
        case .overMRV:
            return .compromised
        case .inRange:
            let midpoint = Double(mev + mrv) / 2
            return sets >= midpoint ? .primed : .ready
        }
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

/// Plain-language weekly volume position vs MEV/MRV. Prefer over `HelmState.label` on volume surfaces.
public enum VolumeLandmarkStatus: String, Sendable, CaseIterable {
    case belowMEV
    case inRange
    case overMRV

    public static func resolve(sets: Double, mev: Int, mrv: Int) -> VolumeLandmarkStatus {
        if sets < Double(mev) { return .belowMEV }
        if sets > Double(mrv) { return .overMRV }
        return .inRange
    }

    public var label: String {
        switch self {
        case .belowMEV: "below MEV"
        case .inRange: "in range"
        case .overMRV: "over MRV"
        }
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
