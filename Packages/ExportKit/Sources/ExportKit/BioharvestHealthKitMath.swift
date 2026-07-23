import Foundation

/// Pure calendar and sleep-interval helpers matching bioharvest `BioharvestHealthKitMath`.
public enum BioharvestHealthKitMath: Sendable {
    public static func startOfCalendarDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func inclusiveEndOfCalendarDay(_ date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dayStart)
            ?? dayStart.addingTimeInterval(86_399)
    }

    public static func exclusiveEndOfCalendarDay(_ date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
    }

    public static func dailyQueryBounds(
        from rangeStartDay: Date,
        through rangeEndDay: Date,
        calendar: Calendar,
        now: Date = Date()
    ) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: rangeStartDay)

        if calendar.isDate(rangeEndDay, inSameDayAs: now) {
            return (start, now)
        }

        let inclusiveEnd = inclusiveEndOfCalendarDay(rangeEndDay, calendar: calendar)
        let exclusiveEnd = calendar.date(byAdding: .second, value: 1, to: inclusiveEnd)
            ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: rangeEndDay))
            ?? inclusiveEnd.addingTimeInterval(1)
        return (start, exclusiveEnd)
    }

    public static func sleepWindowStart(for day: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: dayStart) else {
            return dayStart
        }
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay) ?? previousDay
    }

    public static func sleepWindowEnd(for day: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayStart) ?? dayStart
    }

    public static func mergedDurationMinutes(
        from intervals: [(start: Date, end: Date)]
    ) -> Double? {
        let valid = intervals.filter { $0.end > $0.start }
        guard !valid.isEmpty else { return nil }

        let sorted = valid.sorted { $0.start < $1.start }
        var merged: [(start: Date, end: Date)] = []

        for interval in sorted {
            if var last = merged.popLast() {
                if interval.start <= last.end {
                    last.end = max(last.end, interval.end)
                    merged.append(last)
                } else {
                    merged.append(last)
                    merged.append(interval)
                }
            } else {
                merged.append(interval)
            }
        }

        let totalSeconds = merged.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        return totalSeconds / 60.0
    }

    public static func enumerateDays(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var current = startOfCalendarDay(start, calendar: calendar)
        let lastDay = startOfCalendarDay(end, calendar: calendar)
        while current <= lastDay {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = startOfCalendarDay(next, calendar: calendar)
        }
        return days
    }
}
