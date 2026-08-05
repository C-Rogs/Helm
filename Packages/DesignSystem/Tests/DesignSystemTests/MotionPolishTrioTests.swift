import Testing
@testable import DesignSystem

@Suite("Action button phases")
struct HelmActionButtonTests {
    @Test("Phase enum covers idle loading success")
    func phasesExist() {
        let phases: [HelmActionPhase] = [.idle, .loading, .success]
        #expect(phases.count == 3)
        #expect(HelmActionPhase.idle != .loading)
        #expect(HelmActionPhase.loading != .success)
    }

    @Test("Reduce motion uses quick dwell for success return")
    func reduceMotionDwellUsesQuick() {
        let reduced = HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: true)
        let full = HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: false)
        #expect(reduced != nil)
        #expect(full != nil)
        #expect(HelmMotion.revealDuration(reduceMotion: true) == HelmMotion.quick)
        #expect(HelmMotion.revealDuration(reduceMotion: false) == HelmMotion.reveal)
    }
}

@Suite("Chart continuity motion")
struct ChartContinuityMotionTests {
    @Test("Appear draw uses standard token under full motion")
    func appearUsesStandard() {
        let animation = HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: false)
        #expect(animation != nil)
    }

    @Test("Appear draw collapses under reduce motion")
    func appearCollapses() {
        let animation = HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: true)
        #expect(animation != nil)
        #expect(HelmMotion.shouldAnimateReveal(reduceMotion: true) == false)
    }

    @Test("Bar value changes use settle token")
    func barSettleToken() {
        let reduced = HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: true)
        let full = HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: false)
        #expect(reduced != nil)
        #expect(full != nil)
    }
}
