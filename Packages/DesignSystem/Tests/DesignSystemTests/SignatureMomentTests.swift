import Testing
@testable import DesignSystem

@Suite("Signature moment motion")
struct SignatureMomentTests {
    @Test("Arc draw honors reduce motion")
    func arcDrawReduceMotion() {
        #expect(HelmMotion.shouldAnimateReveal(reduceMotion: true) == false)
        #expect(HelmMotion.shouldAnimateReveal(reduceMotion: false) == true)
    }

    @Test("Arc progress uses standard animation token")
    func arcProgressAnimation() {
        let reduced = HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: true)
        let full = HelmMotion.animation(HelmMotion.standardAnimation, reduceMotion: false)
        #expect(reduced != nil)
        #expect(full != nil)
    }

    @Test("Contributor reveal stagger collapses under reduce motion")
    func contributorStaggerReduceMotion() {
        #expect(HelmMotion.staggerDelay(index: 3, step: 0.05, reduceMotion: true) == 0)
        #expect(HelmMotion.staggerDelay(index: 3, step: 0.05, reduceMotion: false) == 0.15)
    }

    @Test("Daily reveal gate still fires once per day")
    func revealGateOncePerDay() {
        var gate = DailyRevealGate()
        #expect(gate.shouldReveal(for: "2026-07-24") == true)
        gate.markRevealed(for: "2026-07-24")
        #expect(gate.shouldReveal(for: "2026-07-24") == false)
    }

    @Test("PR haptic still fires once per record key")
    func prOncePerKey() {
        let key = PersonalRecordHapticPolicy.stableKey(exerciseID: "bench", metricType: "maxWeight")
        let played: Set<String> = [key]
        #expect(
            PersonalRecordHapticPolicy.newRecordKeys(recordKeys: [key], alreadyPlayed: played).isEmpty
        )
    }
}
