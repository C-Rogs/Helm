import Foundation

/// Aggregates persisted sleep intervals into nightly totals aligned with Apple Health.
///
/// Uses an 18:00–18:00 local window on the wake calendar day and merges overlapping
/// intervals before summing. Matches `BioharvestHealthKitMath` / Schema V2 export math.
public enum SleepAggregation: Sendable {
    /// Start of the sleep window for a wake calendar day (18:00 on the previous day).
    public static func sleepWindowStart(for wakeDay: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: wakeDay)
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: dayStart) else {
            return dayStart
        }
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay) ?? previousDay
    }

    /// End of the sleep window for a wake calendar day (18:00 on that day).
    public static func sleepWindowEnd(for wakeDay: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: wakeDay)
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayStart) ?? dayStart
    }

    /// Total asleep hours for `helmDay`, using the 18:00–18:00 wake-day window.
    public static func totalHours(
        for helmDay: HelmDay,
        records: [SleepRecord],
        calendar: Calendar
    ) -> Double? {
        guard let wakeDay = calendar.date(from: helmDay.dateComponents()) else { return nil }
        let windowStart = sleepWindowStart(for: wakeDay, calendar: calendar)
        let windowEnd = sleepWindowEnd(for: wakeDay, calendar: calendar)
        return totalHours(from: records, windowStart: windowStart, windowEnd: windowEnd)
    }

    /// Merges overlapping clipped intervals and returns total asleep hours, if any.
    public static func totalHours(
        from records: [SleepRecord],
        windowStart: Date,
        windowEnd: Date
    ) -> Double? {
        let intervals = records.compactMap { record -> (start: Date, end: Date)? in
            clip(record.start ... record.end, to: windowStart ... windowEnd)
        }
        guard let minutes = mergedDurationMinutes(from: intervals) else { return nil }
        return minutes / 60.0
    }

    /// Merges overlapping intervals and returns total duration in minutes.
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

    private static func clip(
        _ interval: ClosedRange<Date>,
        to window: ClosedRange<Date>
    ) -> (start: Date, end: Date)? {
        let start = max(interval.lowerBound, window.lowerBound)
        let end = min(interval.upperBound, window.upperBound)
        guard end > start else { return nil }
        return (start, end)
    }
}
