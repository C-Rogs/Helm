import Testing
@testable import DesignSystem

@Suite("Week ahead schedule snapshots")
struct WeekAheadScheduleSnapshotTests {
    @Test("week ahead fixture snapshot")
    func weekAheadFixture() {
        let text = WeekAheadScheduleSnapshot.text(for: .weekAheadFixture)
        #expect(text == weekAheadSnapshotText)
        #expect(text.contains("status=today"))
        #expect(text.contains("status=completed"))
        #expect(text.contains("status=missed"))
    }

    @Test("empty fixture snapshot")
    func emptyFixture() {
        let text = WeekAheadScheduleSnapshot.text(for: WeekAheadScheduleModel(rows: []))
        #expect(text == "# Week ahead\n- none")
    }
}

private let weekAheadSnapshotText = """
# Week ahead
- Today: Pull | status=today | today=true | note=Push already logged this week - Pull is next.
- Wed · Jul 29: Legs | status=upcoming | today=false
- Thu · Jul 30: Push | status=upcoming | today=false
- Mon · Jul 27: Push | status=completed | today=false
- Sun · Jul 26: Legs | status=missed | today=false
"""
