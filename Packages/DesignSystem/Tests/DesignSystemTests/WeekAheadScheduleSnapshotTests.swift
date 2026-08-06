import Testing
@testable import DesignSystem

@Suite("Week ahead schedule snapshots")
struct WeekAheadScheduleSnapshotTests {
    @Test("week ahead fixture snapshot")
    func weekAheadFixture() {
        let text = WeekAheadScheduleSnapshot.text(for: .weekAheadFixture)
        #expect(text == weekAheadSnapshotText)
        #expect(text.contains("status=today"))
        #expect(text.contains("status=rest"))
        #expect(text.contains("status=upcoming"))
    }

    @Test("empty fixture snapshot")
    func emptyFixture() {
        let text = WeekAheadScheduleSnapshot.text(for: WeekAheadScheduleModel(rows: []))
        #expect(text == "# Week ahead\n- none")
    }

    @Test("collapsed summary highlights next session")
    func collapsedSummary() {
        #expect(
            WeekAheadScheduleModel.weekAheadFixture.collapsedSummary
                == "3 sessions · 4 rest · Pull next"
        )
        #expect(WeekAheadScheduleModel(rows: []).collapsedSummary == "No days planned")
    }

    @Test("chronological rows sort by planned day")
    func chronologicalRows() {
        let ordered = WeekAheadScheduleModel.weekAheadFixture.chronologicalRows.map(\.id)
        #expect(ordered == [
            "2026-07-28",
            "2026-07-29",
            "2026-07-30",
            "2026-07-31",
            "2026-08-01",
            "2026-08-02",
            "2026-08-03"
        ])
    }
}

private let weekAheadSnapshotText = """
# Week ahead
- Today: Pull | status=today | today=true | note=Push already logged this week - Pull is next.
- Wed · Jul 29: Rest | status=rest | today=false
- Thu · Jul 30: Legs | status=upcoming | today=false
- Fri · Jul 31: Rest | status=rest | today=false
- Sat · Aug 1: Push | status=upcoming | today=false
- Sun · Aug 2: Rest | status=rest | today=false
- Mon · Aug 3: Rest | status=rest | today=false
"""
