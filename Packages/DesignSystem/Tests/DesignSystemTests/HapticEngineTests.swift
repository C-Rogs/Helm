import Foundation
import Testing
@testable import DesignSystem

@MainActor
@Suite("Haptic engine")
struct HapticEngineTests {
    @Test("Disabled haptics no-op")
    func disabledHaptics() async {
        let defaults = UserDefaults(suiteName: "HapticEngineTests.disabled")!
        defaults.removePersistentDomain(forName: "HapticEngineTests.disabled")
        let coordinator = HelmThemeCoordinator(defaults: defaults)
        coordinator.hapticsEnabled = false

        let hardware = MockHapticHardware()
        let engine = HapticEngine(hardware: hardware, preferences: coordinator)

        await engine.play(.setLogged, lowPowerMode: false)

        #expect(hardware.playedPatterns.isEmpty)
    }

    @Test("Each pattern resolves on capable hardware")
    func allPatternsResolve() async {
        let defaults = UserDefaults(suiteName: "HapticEngineTests.patterns")!
        defaults.removePersistentDomain(forName: "HapticEngineTests.patterns")
        let coordinator = HelmThemeCoordinator(defaults: defaults)
        coordinator.hapticsEnabled = true

        let hardware = MockHapticHardware()
        let engine = HapticEngine(hardware: hardware, preferences: coordinator)

        for pattern in HelmHaptic.allCases {
            await engine.play(pattern, lowPowerMode: false)
        }

        #expect(hardware.playedPatterns.count == HelmHaptic.allCases.count)
    }

    @Test("No hardware uses fallback without crashing")
    func noHardwareFallback() async {
        let defaults = UserDefaults(suiteName: "HapticEngineTests.fallback")!
        defaults.removePersistentDomain(forName: "HapticEngineTests.fallback")
        let coordinator = HelmThemeCoordinator(defaults: defaults)
        coordinator.hapticsEnabled = true

        let hardware = MockHapticHardware()
        hardware.supportsHapticsValue = false
        let engine = HapticEngine(hardware: hardware, preferences: coordinator)

        await engine.play(.selection, lowPowerMode: false)
        #expect(hardware.playedPatterns.isEmpty)
    }

    @Test("Low power readiness reveal still plays")
    func lowPowerReadinessReveal() async throws {
        _ = try HapticPatternBuilder.pattern(for: .readinessReveal, lowPowerMode: true)
    }

    @Test("Built patterns compile for every case")
    func builtPatternsCompile() throws {
        for pattern in HelmHaptic.allCases {
            _ = try HapticPatternBuilder.pattern(for: pattern, lowPowerMode: false)
            _ = try HapticPatternBuilder.pattern(for: pattern, lowPowerMode: true)
        }
    }

    @Test("Fallback resolver covers every pattern")
    func fallbackResolverCoverage() {
        for pattern in HelmHaptic.allCases {
            _ = HapticFallbackResolver.fallback(for: pattern)
        }
    }

    @Test("Selection play skips Core Haptics hop")
    func selectionIsImmediate() {
        let defaults = UserDefaults(suiteName: "HapticEngineTests.selection")!
        defaults.removePersistentDomain(forName: "HapticEngineTests.selection")
        let coordinator = HelmThemeCoordinator(defaults: defaults)
        coordinator.hapticsEnabled = true

        let hardware = MockHapticHardware()
        hardware.isEngineReadyValue = true
        let engine = HapticEngine(hardware: hardware, preferences: coordinator)

        engine.play(.selection)

        #expect(hardware.playedImmediatePatterns.isEmpty)
        #expect(hardware.playedPatterns.isEmpty)
    }

    @Test("Set logged plays immediately when engine is warm")
    func setLoggedImmediateWhenWarm() {
        let defaults = UserDefaults(suiteName: "HapticEngineTests.setLoggedWarm")!
        defaults.removePersistentDomain(forName: "HapticEngineTests.setLoggedWarm")
        let coordinator = HelmThemeCoordinator(defaults: defaults)
        coordinator.hapticsEnabled = true

        let hardware = MockHapticHardware()
        hardware.isEngineReadyValue = true
        let engine = HapticEngine(hardware: hardware, preferences: coordinator)

        engine.play(.setLogged)

        #expect(hardware.playedImmediatePatterns == [.setLogged])
        #expect(hardware.playedPatterns.isEmpty)
    }

    @Test("Same-frame patterns are the tap ticks")
    func sameFramePatterns() {
        #expect(HelmHaptic.selection.playsOnSameFrame)
        #expect(HelmHaptic.setLogged.playsOnSameFrame)
        #expect(HelmHaptic.mealConfirmed.playsOnSameFrame)
        #expect(HelmHaptic.clampRejected.playsOnSameFrame)
        #expect(HelmHaptic.restCountInStep(remainingSeconds: 3).playsOnSameFrame)
        #expect(!HelmHaptic.readinessReveal.playsOnSameFrame)
        #expect(!HelmHaptic.prHit.playsOnSameFrame)
    }
}
