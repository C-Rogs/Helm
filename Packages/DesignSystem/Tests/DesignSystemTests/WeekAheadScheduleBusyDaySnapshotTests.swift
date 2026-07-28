import Testing
@testable import DesignSystem

@Suite("Week ahead busy-day hint snapshots")
struct WeekAheadScheduleBusyDaySnapshotTests {
    @Test("busy-day hints render in snapshot text")
    func busyDayHints() {
        let text = WeekAheadScheduleSnapshot.text(for: .busyDayFixture)
        #expect(text.contains("busy=Busy · 5h scheduled"))
        #expect(text.contains("busy=Busy · 3 events"))
    }
}
