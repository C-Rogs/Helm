import Testing
@testable import Core

@Suite("Busy day hint policy")
struct BusyDayHintPolicyTests {
    @Test("all-day event marks busy day")
    func allDayEvent() {
        let load = CalendarDayLoad(timedEventCount: 0, scheduledSeconds: 0, hasAllDayEvent: true)
        #expect(BusyDayHintPolicy.hint(for: load) == "Busy day")
    }

    @Test("four or more scheduled hours marks busy day")
    func scheduledHours() {
        let load = CalendarDayLoad(timedEventCount: 2, scheduledSeconds: 4 * 3_600, hasAllDayEvent: false)
        #expect(BusyDayHintPolicy.hint(for: load) == "Busy · 4h scheduled")
    }

    @Test("three or more timed events marks busy day")
    func eventCount() {
        let load = CalendarDayLoad(timedEventCount: 3, scheduledSeconds: 90 * 60, hasAllDayEvent: false)
        #expect(BusyDayHintPolicy.hint(for: load) == "Busy · 3 events")
    }

    @Test("light days do not surface a hint")
    func lightDay() {
        let load = CalendarDayLoad(timedEventCount: 2, scheduledSeconds: 2 * 3_600, hasAllDayEvent: false)
        #expect(BusyDayHintPolicy.hint(for: load) == nil)
    }

    @Test("day loads map to hints by day")
    func hintsFromLoads() {
        let day = HelmDay(year: 2026, month: 7, day: 28)
        let quietDay = HelmDay(year: 2026, month: 7, day: 29)
        let hints = BusyDayHintPolicy.hints(from: [
            day: CalendarDayLoad(timedEventCount: 2, scheduledSeconds: 5 * 3_600, hasAllDayEvent: false),
            quietDay: CalendarDayLoad(timedEventCount: 1, scheduledSeconds: 3_600, hasAllDayEvent: false)
        ])

        #expect(hints[day] == "Busy · 5h scheduled")
        #expect(hints[quietDay] == nil)
    }
}
