import Testing
@testable import DesignSystem

@Suite("Week ahead drift scenario snapshots")
struct WeekAheadScheduleDriftSnapshotTests {
    @Test("shifted session renders moved indicator")
    func shiftedSession() {
        let text = WeekAheadScheduleSnapshot.text(for: .driftScenarioFixture)
        #expect(text.contains("status=shifted"))
        #expect(text.contains("drift=Was Sun · Jul 20"))
    }

    @Test("skipped sessions render skipped indicator")
    func skippedSessions() {
        let text = WeekAheadScheduleSnapshot.text(for: .driftScenarioFixture)
        let skippedCount = text.components(separatedBy: "status=skipped").count - 1
        #expect(skippedCount == 2)
    }

    @Test("drift scenario fixture snapshot")
    func driftScenarioFixture() {
        let text = WeekAheadScheduleSnapshot.text(for: .driftScenarioFixture)
        #expect(text == driftScenarioSnapshotText)
    }
}

private let driftScenarioSnapshotText = """
# Week ahead
- Tue · Jul 22: Pull | status=shifted | today=false | note=Logged two days late - session shifted. | drift=Was Sun · Jul 20
- Mon · Jul 20: Push | status=skipped | today=false
- Wed · Jul 22: Legs | status=skipped | today=false
- Fri · Jul 24: Upper | status=completed | today=false
- Sat · Jul 25: Lower | status=upcoming | today=false
"""
