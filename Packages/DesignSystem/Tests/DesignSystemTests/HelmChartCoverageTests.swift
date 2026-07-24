import Testing
@testable import DesignSystem

@Suite("Helm chart coverage")
struct HelmChartCoverageTests {
    @Test("reduce motion reveal duration")
    func reduceMotionQuick() {
        #expect(HelmMotion.revealDuration(reduceMotion: true) == HelmMotion.quick)
    }
}
