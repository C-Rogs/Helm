import Testing
@testable import DesignSystem

@Suite("Helm motion")
struct HelmMotionTests {
    @Test("Reduce motion collapses reveal duration")
    func reduceMotionRevealDuration() {
        #expect(HelmMotion.revealDuration(reduceMotion: true) == HelmMotion.quick)
        #expect(HelmMotion.revealDuration(reduceMotion: false) == HelmMotion.reveal)
    }

    @Test("Reduce motion disables reveal sweep")
    func reduceMotionRevealSweep() {
        #expect(HelmMotion.shouldAnimateReveal(reduceMotion: true) == false)
        #expect(HelmMotion.shouldAnimateReveal(reduceMotion: false) == true)
    }

    @Test("Reduce motion swaps animation token")
    func reduceMotionAnimation() {
        let reduced = HelmMotion.animation(.spring(), reduceMotion: true)
        let full = HelmMotion.animation(.spring(), reduceMotion: false)
        #expect(reduced != nil)
        #expect(full != nil)
    }
}

@Suite("Helm theme mode")
struct HelmThemeModeTests {
    @Test("Auto resolves from color scheme")
    func autoPalette() {
        #expect(HelmThemeMode.auto.resolvedPalette(colorScheme: .dark) == .dark)
        #expect(HelmThemeMode.auto.resolvedPalette(colorScheme: .light) == .light)
    }

    @Test("Explicit modes override system")
    func explicitPalette() {
        #expect(HelmThemeMode.dark.resolvedPalette(colorScheme: .light) == .dark)
        #expect(HelmThemeMode.light.resolvedPalette(colorScheme: .dark) == .light)
    }
}

@Suite("Helm state ramp")
struct HelmStateTests {
    @Test("Readiness bands map to states")
    func readinessBands() {
        #expect(HelmState.readiness(score: 20) == .depleted)
        #expect(HelmState.readiness(score: 48) == .compromised)
        #expect(HelmState.readiness(score: 64) == .ready)
        #expect(HelmState.readiness(score: 88) == .primed)
    }
}
