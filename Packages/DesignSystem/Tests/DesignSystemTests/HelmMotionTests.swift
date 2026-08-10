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

    @Test("Reduce motion collapses stagger delay")
    func reduceMotionStaggerDelay() {
        #expect(HelmMotion.staggerDelay(index: 4, reduceMotion: true) == 0)
        #expect(HelmMotion.staggerDelay(index: 4, reduceMotion: false) == 0.16)
        #expect(
            HelmMotion.staggerDelay(index: 4, baseDelay: 0.28, reduceMotion: false) == 0.44
        )
        #expect(
            HelmMotion.staggerDelay(index: 4, baseDelay: 0.28, reduceMotion: true) == 0
        )
    }

    @Test("Reduce motion disables skeleton shimmer")
    func reduceMotionShimmer() {
        #expect(HelmMotion.usesShimmer(reduceMotion: true) == false)
        #expect(HelmMotion.usesShimmer(reduceMotion: false) == true)
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

@Suite("Daily reveal gate")
struct DailyRevealGateTests {
    @Test("Reveal only once per day key")
    func oncePerDay() {
        var gate = DailyRevealGate()
        #expect(gate.shouldReveal(for: "2026-07-23") == true)
        gate.markRevealed(for: "2026-07-23")
        #expect(gate.shouldReveal(for: "2026-07-23") == false)
    }

    @Test("New day resets reveal eligibility")
    func dayBoundary() {
        var gate = DailyRevealGate(lastRevealedDay: "2026-07-22")
        #expect(gate.shouldReveal(for: "2026-07-22") == false)
        #expect(gate.shouldReveal(for: "2026-07-23") == true)
        gate.markRevealed(for: "2026-07-23")
        #expect(gate.shouldReveal(for: "2026-07-23") == false)
        #expect(gate.shouldReveal(for: "2026-07-24") == true)
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

    @Test("Volume landmark status uses plain MEV/MRV copy")
    func volumeLandmarkStatus() {
        #expect(VolumeLandmarkStatus.resolve(sets: 5, mev: 8, mrv: 18) == .belowMEV)
        #expect(VolumeLandmarkStatus.resolve(sets: 5, mev: 8, mrv: 18).label == "below MEV")
        #expect(VolumeLandmarkStatus.resolve(sets: 12, mev: 8, mrv: 18) == .inRange)
        #expect(VolumeLandmarkStatus.resolve(sets: 12, mev: 8, mrv: 18).label == "in range")
        #expect(VolumeLandmarkStatus.resolve(sets: 22, mev: 8, mrv: 18) == .overMRV)
        #expect(VolumeLandmarkStatus.resolve(sets: 22, mev: 8, mrv: 18).label == "over MRV")
    }

    @Test("volumeWeekly fill colors still map under/over landmarks")
    func volumeWeeklyFill() {
        #expect(HelmState.volumeWeekly(sets: 5, mev: 8, mrv: 18) == .depleted)
        #expect(HelmState.volumeWeekly(sets: 10, mev: 8, mrv: 18) == .ready)
        #expect(HelmState.volumeWeekly(sets: 14, mev: 8, mrv: 18) == .primed)
        #expect(HelmState.volumeWeekly(sets: 22, mev: 8, mrv: 18) == .compromised)
    }
}
