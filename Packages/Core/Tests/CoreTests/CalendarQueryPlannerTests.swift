import Foundation
import Testing
@testable import Core

@Suite("Calendar query planner")
struct CalendarQueryPlannerTests {
    private let today = HelmDay(year: 2026, month: 9, day: 1)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("range without search stays lookback ending today")
    func rangeLookback() {
        let window = CalendarQueryPlanner.resolve(
            kind: .range,
            today: today,
            weekAheadHorizon: 7,
            calendar: calendar
        )
        #expect(window.startDay == HelmDay(year: 2026, month: 8, day: 26))
        #expect(window.endDay == today)
        #expect(window.queryLabel == "range lookback=7")
        #expect(window.search == nil)
        #expect(window.omitEmptyDays == false)
    }

    @Test("named search looks ahead 365 days from today")
    func searchLookahead() {
        let window = CalendarQueryPlanner.resolve(
            kind: .range,
            today: today,
            search: "Italy",
            weekAheadHorizon: 7,
            calendar: calendar
        )
        #expect(window.startDay == today)
        #expect(window.endDay == today.adding(days: 364, calendar: calendar))
        #expect(window.search == "Italy")
        #expect(window.omitEmptyDays)
        #expect(window.queryLabel.contains("search=\"Italy\""))
        #expect(window.queryLabel.contains("lookahead=365"))
    }

    @Test("clamps lookahead to 365")
    func clampsLookahead() {
        let window = CalendarQueryPlanner.resolve(
            kind: .range,
            today: today,
            lookaheadDays: 400,
            search: "Italy",
            weekAheadHorizon: 7,
            calendar: calendar
        )
        #expect(window.endDay == today.adding(days: 364, calendar: calendar))
    }

    @Test("today plus search expands into a lookahead window")
    func todaySearchExpands() {
        let window = CalendarQueryPlanner.resolve(
            kind: .today,
            today: today,
            search: "Italy",
            weekAheadHorizon: 7,
            calendar: calendar
        )
        #expect(window.startDay == today)
        #expect(window.endDay == today.adding(days: 364, calendar: calendar))
        #expect(window.omitEmptyDays)
    }

    @Test("day plus search without helmDay looks ahead, not today")
    func daySearchWithoutDateLooksAhead() {
        let window = CalendarQueryPlanner.resolve(
            kind: .day,
            today: today,
            search: "Italy",
            weekAheadHorizon: 7,
            calendar: calendar
        )
        #expect(window.startDay == today)
        #expect(window.endDay == today.adding(days: 364, calendar: calendar))
        #expect(window.search == "Italy")
        #expect(window.omitEmptyDays)
    }

    @Test("day plus search with helmDay stays on that day")
    func daySearchWithDateStays() {
        let window = CalendarQueryPlanner.resolve(
            kind: .day,
            today: today,
            helmDay: "2026-11-10",
            search: "Italy",
            weekAheadHorizon: 7,
            calendar: calendar
        )
        #expect(window.startDay == HelmDay(year: 2026, month: 11, day: 10))
        #expect(window.endDay == window.startDay)
    }

    @Test("title match is case insensitive and filters other events")
    func titleSearchFilter() {
        let italyDay = HelmDay(year: 2026, month: 11, day: 10)
        let footballDay = HelmDay(year: 2026, month: 9, day: 1)
        let start = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 9, day: 1, hour: 19))!
        let days = [
            CalendarDayDetail(
                helmDay: footballDay,
                load: CalendarDayLoad(timedEventCount: 1, scheduledSeconds: 3_600, hasAllDayEvent: false),
                events: [
                    CalendarEventDetail(title: "Football", start: start, end: start.addingTimeInterval(3_600), isAllDay: false)
                ]
            ),
            CalendarDayDetail(
                helmDay: italyDay,
                load: CalendarDayLoad(
                    timedEventCount: 0,
                    scheduledSeconds: 0,
                    hasAllDayEvent: true,
                    allDayEventTitles: ["Trip to Italy"]
                ),
                events: [
                    CalendarEventDetail(title: "Trip to Italy", start: start, end: start, isAllDay: true)
                ]
            )
        ]
        let matched = CalendarQueryPlanner.applySearch(days, search: "italy")
        #expect(matched.count == 1)
        #expect(matched.first?.helmDay == italyDay)
        #expect(matched.first?.load.hasAllDayEvent == true)
        #expect(CalendarQueryPlanner.titleMatches("Trip to Italy", search: "ITALY"))
        #expect(CalendarQueryPlanner.titleMatches("Italia", search: "Italy"))
        #expect(CalendarQueryPlanner.titleMatches("Trip to Italy", search: "Italia"))
    }

    @Test("search matches location and notes")
    func locationAndNotesSearch() {
        let start = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 11, day: 10, hour: 9))!
        let holiday = CalendarEventDetail(
            title: "Holiday",
            start: start,
            end: start,
            isAllDay: true,
            location: "Rome, Italy"
        )
        let noteOnly = CalendarEventDetail(
            title: "Trip",
            start: start,
            end: start,
            isAllDay: true,
            notes: "flights to Italy booked"
        )
        #expect(CalendarQueryPlanner.eventMatches(holiday, search: "italy"))
        #expect(CalendarQueryPlanner.eventMatches(noteOnly, search: "italy"))
        let days = [
            CalendarDayDetail(
                helmDay: HelmDay(year: 2026, month: 11, day: 10),
                load: CalendarDayLoad(timedEventCount: 0, scheduledSeconds: 0, hasAllDayEvent: true),
                events: [holiday]
            )
        ]
        #expect(CalendarQueryPlanner.applySearch(days, search: "italy").count == 1)
    }

    @Test("load rebuilds from matched events only")
    func loadFromEvents() {
        let start = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 9, day: 1, hour: 9))!
        let load = CalendarDayLoad.from(events: [
            CalendarEventDetail(title: "Standup", start: start, end: start.addingTimeInterval(3_600), isAllDay: false),
            CalendarEventDetail(title: "Italy", start: start, end: start, isAllDay: true)
        ])
        #expect(load.timedEventCount == 1)
        #expect(load.scheduledSeconds == 3_600)
        #expect(load.hasAllDayEvent)
        #expect(load.allDayEventTitles == ["Italy"])
    }

    @Test("week ahead without search stays the engine horizon")
    func weekAheadUnchanged() {
        let window = CalendarQueryPlanner.resolve(
            kind: .weekAhead,
            today: today,
            weekAheadHorizon: 7,
            calendar: calendar
        )
        #expect(window.endDay == HelmDay(year: 2026, month: 9, day: 7))
        #expect(window.search == nil)
        #expect(window.omitEmptyDays == false)
        #expect(window.queryLabel == "weekAhead")
    }
}

@Suite("Calendar event day span")
struct CalendarEventDaySpanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("all-day exclusive end spans each occupied day")
    func allDayExclusiveEnd() {
        let start = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 11, day: 10))!
        let end = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 11, day: 13))!
        let windowStart = HelmDay(year: 2026, month: 11, day: 1)
        let windowEnd = HelmDay(year: 2026, month: 11, day: 30)
        let days = CalendarEventDaySpan.helmDays(
            start: start,
            end: end,
            isAllDay: true,
            windowStart: windowStart,
            windowEnd: windowEnd,
            calendar: calendar
        )
        #expect(days == [
            HelmDay(year: 2026, month: 11, day: 10),
            HelmDay(year: 2026, month: 11, day: 11),
            HelmDay(year: 2026, month: 11, day: 12)
        ])
    }

    @Test("clamps all-day span to the query window")
    func clampsToWindow() {
        let start = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 11, day: 10))!
        let end = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 11, day: 20))!
        let days = CalendarEventDaySpan.helmDays(
            start: start,
            end: end,
            isAllDay: true,
            windowStart: HelmDay(year: 2026, month: 11, day: 12),
            windowEnd: HelmDay(year: 2026, month: 11, day: 14),
            calendar: calendar
        )
        #expect(days == [
            HelmDay(year: 2026, month: 11, day: 12),
            HelmDay(year: 2026, month: 11, day: 13),
            HelmDay(year: 2026, month: 11, day: 14)
        ])
    }
}
