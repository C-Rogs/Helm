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

    @Test("collapsed summary highlights next session")
    func collapsedSummary() {
        #expect(WeekAheadScheduleModel.weekAheadFixture.collapsedSummary == "5 sessions · Pull next")
        #expect(WeekAheadScheduleModel(rows: []).collapsedSummary == "No sessions planned")
    }

    @Test("chronological rows sort by planned day")
    func chronologicalRows() {
        let ordered = WeekAheadScheduleModel.weekAheadFixture.chronologicalRows.map(\.id)
        #expect(ordered == [
            "planned-2026-07-26",
            "planned-2026-07-27",
            "planned-2026-07-28",
            "planned-2026-07-29",
            "planned-2026-07-30"
        ])
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
