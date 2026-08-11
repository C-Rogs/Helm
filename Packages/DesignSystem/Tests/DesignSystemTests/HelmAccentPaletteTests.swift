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

    @Test("Theme mode resolution forwards accent")
    func themeModeForwardsAccent() {
        #expect(HelmThemeMode.dark.resolvedPalette(colorScheme: .light, accent: .preset(.lime)) == HelmPalette.dark)
        #expect(HelmThemeMode.auto.resolvedPalette(colorScheme: .dark, accent: .preset(.lime)) == .dark)
        #expect(HelmThemeMode.auto.resolvedPalette(colorScheme: .dark) == .dark)
    }

    @Test("Accent source persistence round-trips presets and custom")
    func accentSourcePersistence() {
        #expect(HelmAccentSource.fromPersistence(nil) == .default)
        #expect(HelmAccentSource.fromPersistence("preset:cyan") == .default) // cyan removed; falls back
        #expect(HelmAccentSource.fromPersistence("preset:lime") == .preset(.lime))
        #expect(HelmAccentSource.fromPersistence("preset:nope") == .default)

        let custom = HelmAccentSource.custom(baseHex: 0x2EE6E0)
        #expect(HelmAccentSource.fromPersistence(custom.persistenceToken) == custom)
    }

    @Test("Coordinator defaults to lime")
    @MainActor
    func coordinatorAccentPersistence() {
        let suite = "HelmAccentPaletteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let fresh = HelmThemeCoordinator(defaults: defaults)
        #expect(fresh.accentSource == .preset(.lime))
        #expect(fresh.accentPreset == .lime)

        defaults.removePersistentDomain(forName: suite)
    }
}
