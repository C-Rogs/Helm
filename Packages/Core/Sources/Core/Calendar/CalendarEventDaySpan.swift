import Foundation

/// Days an EventKit event occupies inside a query window.
/// All-day EventKit `end` is exclusive (midnight after the last day).
public enum CalendarEventDaySpan: Sendable {
    public static func helmDays(
        start: Date,
        end: Date,
        isAllDay: Bool,
        windowStart: HelmDay,
        windowEnd: HelmDay,
        calendar: Calendar,
        cutoff: DayCutoff = .default
    ) -> [HelmDay] {
        let lastInstant = end > start ? end.addingTimeInterval(-1) : start
        let first = isAllDay
            ? HelmDay.calendarDay(for: start, calendar: calendar)
            : HelmDay.day(for: start, cutoff: cutoff, calendar: calendar)
        let last = isAllDay
            ? HelmDay.calendarDay(for: lastInstant, calendar: calendar)
            : HelmDay.day(for: lastInstant, cutoff: cutoff, calendar: calendar)
        let clampedStart = first < windowStart ? windowStart : first
        let clampedEnd = last > windowEnd ? windowEnd : last
        guard clampedStart <= clampedEnd else { return [] }

        var days: [HelmDay] = []
        var cursor = clampedStart
        while cursor <= clampedEnd {
            days.append(cursor)
            cursor = cursor.adding(days: 1, calendar: calendar)
            if days.count > 400 {
                break
            }
        }
        return days
    }
}
