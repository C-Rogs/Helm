import Foundation
import Testing
@testable import DesignSystem

@Suite("Helm accent palette")
struct HelmAccentPaletteTests {
    @Test("Lime dark and light match named statics")
    func limeParityWithStatics() {
        #expect(HelmPalette.resolved(appearance: .dark, accent: .preset(.lime)) == .dark)
        #expect(HelmPalette.resolved(appearance: .light, accent: .preset(.lime)) == .light)
        #expect(HelmPalette.resolved(appearance: .dark, accent: .default) == .dark)
        #expect(HelmPalette.resolved(appearance: .light, accent: .default) == .light)
    }

    @Test("Cyan changes accent family only")
    func cyanTouchesAccentFamilyOnly() {
        let limeDark = HelmPalette.dark
        let cyanDark = HelmPalette.resolved(appearance: .dark, accent: .preset(.cyan))

        #expect(cyanDark != limeDark)
        #expect(cyanDark.canvas == limeDark.canvas)
        #expect(cyanDark.surface == limeDark.surface)
        #expect(cyanDark.fg == limeDark.fg)
        #expect(cyanDark.depleted == limeDark.depleted)
        #expect(cyanDark.compromised == limeDark.compromised)
        #expect(cyanDark.accent != limeDark.accent)
        #expect(cyanDark.primed != limeDark.primed)
        #expect(cyanDark.ready != limeDark.ready)

        let limeLight = HelmPalette.light
        let cyanLight = HelmPalette.resolved(appearance: .light, accent: .preset(.cyan))
        #expect(cyanLight.canvas == limeLight.canvas)
        #expect(cyanLight.depleted == limeLight.depleted)
        #expect(cyanLight.compromised == limeLight.compromised)
        #expect(cyanLight.accent != limeLight.accent)
    }

    @Test("Cyan light uses darkened text accent and bright fill")
    func cyanLightAccentFillSplit() {
        let cyanLight = HelmPalette.resolved(appearance: .light, accent: .preset(.cyan))
        #expect(cyanLight.accentFill != nil)
        if let fill = cyanLight.accentFill {
            #expect(fill != cyanLight.accent)
        }
        #expect(cyanLight.primed == cyanLight.accent)
        #expect(cyanLight.chartLine == cyanLight.accent)
    }

    @Test("Theme mode resolution forwards accent")
    func themeModeForwardsAccent() {
        let cyan = HelmPalette.resolved(appearance: .dark, accent: .preset(.cyan))
        #expect(HelmThemeMode.dark.resolvedPalette(colorScheme: .light, accent: .preset(.cyan)) == cyan)
        #expect(HelmThemeMode.auto.resolvedPalette(colorScheme: .dark, accent: .preset(.cyan)) == cyan)
        #expect(HelmThemeMode.auto.resolvedPalette(colorScheme: .dark) == .dark)
    }

    @Test("Accent source persistence round-trips presets and custom")
    func accentSourcePersistence() {
        #expect(HelmAccentSource.fromPersistence(nil) == .default)
        #expect(HelmAccentSource.fromPersistence("preset:cyan") == .preset(.cyan))
        #expect(HelmAccentSource.fromPersistence("cyan") == .preset(.cyan))
        #expect(HelmAccentSource.fromPersistence("preset:nope") == .default)

        let custom = HelmAccentSource.custom(baseHex: 0x2EE6E0)
        #expect(HelmAccentSource.fromPersistence(custom.persistenceToken) == custom)
    }

    @Test("Coordinator defaults to lime and persists cyan")
    @MainActor
    func coordinatorAccentPersistence() {
        let suite = "HelmAccentPaletteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let fresh = HelmThemeCoordinator(defaults: defaults)
        #expect(fresh.accentSource == .preset(.lime))
        #expect(fresh.accentPreset == .lime)

        fresh.accentSource = .preset(.cyan)
        #expect(defaults.string(forKey: "helm.accentSource") == "preset:cyan")

        let reloaded = HelmThemeCoordinator(defaults: defaults)
        #expect(reloaded.accentSource == .preset(.cyan))
        #expect(reloaded.accentPreset == .cyan)

        defaults.removePersistentDomain(forName: suite)
    }
}
