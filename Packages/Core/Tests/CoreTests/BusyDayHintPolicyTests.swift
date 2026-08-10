import Testing
@testable import Core
import Foundation

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

    @Test("engine busy explanation names threshold that fired")
    func engineBusyExplanation() {
        let allDay = CalendarDayLoad(
            timedEventCount: 0,
            scheduledSeconds: 0,
            hasAllDayEvent: true,
            allDayEventTitles: ["Holiday"]
        )
        #expect(BusyDayHintPolicy.engineBusyExplanation(for: allDay).contains("all_day_event"))
        #expect(BusyDayHintPolicy.engineBusyExplanation(for: allDay).contains("Holiday"))

        let hours = CalendarDayLoad(timedEventCount: 1, scheduledSeconds: 5 * 3_600, hasAllDayEvent: false)
        #expect(BusyDayHintPolicy.engineBusyExplanation(for: hours).contains("scheduled_hours>="))

        let count = CalendarDayLoad(timedEventCount: 3, scheduledSeconds: 90 * 60, hasAllDayEvent: false)
        #expect(BusyDayHintPolicy.engineBusyExplanation(for: count).contains("timed_event_count>="))

        let light = CalendarDayLoad(timedEventCount: 1, scheduledSeconds: 3_600, hasAllDayEvent: false)
        #expect(BusyDayHintPolicy.engineBusyExplanation(for: light).contains("engine_busy=false"))
    }

    @Test("calendar query formatter lists events and busy reason")
    func queryFormatter() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = HelmDay(year: 2026, month: 8, day: 7)
        let start = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 8, day: 7, hour: 9))!
        let end = start.addingTimeInterval(3_600)
        let detail = CalendarDayDetail(
            helmDay: day,
            load: CalendarDayLoad(timedEventCount: 1, scheduledSeconds: 3_600, hasAllDayEvent: false),
            events: [
                CalendarEventDetail(title: "Standup", start: start, end: end, isAllDay: false)
            ]
        )
        let text = CalendarQueryResultFormatter.format(
            query: "today",
            authorizationStatus: "authorized",
            days: [detail],
            calendar: calendar
        )
        #expect(text.contains("query=today"))
        #expect(text.contains("busy_hint=none"))
        #expect(text.contains("engine_busy=false"))
        #expect(text.contains("title=\"Standup\""))
        #expect(text.contains("start=09:00"))
    }

    @Test("calendar query formatter reports unauthorized")
    func queryFormatterUnauthorized() {
        let text = CalendarQueryResultFormatter.format(
            query: "today",
            authorizationStatus: "denied",
            days: []
        )
        #expect(text.contains("error=calendar_unavailable"))
        #expect(text.contains("calendar_status=denied"))
    }
}
