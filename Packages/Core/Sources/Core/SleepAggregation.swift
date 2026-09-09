import Foundation

/// Aggregates persisted sleep intervals into nightly totals aligned with Apple Health.
///
/// Uses an 18:00–18:00 local window on the wake calendar day and merges overlapping
/// intervals before summing. Matches `BioharvestHealthKitMath` / Schema V2 export math.
/// See `Docs/SLEEP-METRICS.md` for the canonical "Time Asleep" definition.
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
        return nightSummary(
            from: records,
            windowStart: windowStart,
            windowEnd: windowEnd
        ).asleepHours
    }

    /// Merges overlapping clipped intervals and returns total asleep hours, if any.
    public static func totalHours(
        from records: [SleepRecord],
        windowStart: Date,
        windowEnd: Date
    ) -> Double? {
        nightSummary(from: records, windowStart: windowStart, windowEnd: windowEnd).asleepHours
    }

    /// Stage-aware nightly totals for a wake-day window.
    public static func nightSummary(
        from records: [SleepRecord],
        windowStart: Date,
        windowEnd: Date
    ) -> SleepNightSummary {
        let orderedRecords = records.sorted { $0.start < $1.start }
        return nightSummary(
            fromRecordsSortedByStart: orderedRecords,
            windowStart: windowStart,
            windowEnd: windowEnd
        )
    }

    /// Builds summaries for consecutive wake days while scanning the supplied records once.
    ///
    /// `fetchOverlapping` already orders its result, but this method also accepts unsorted
    /// input because callers outside Persistence can provide arbitrary sleep records.
    public static func nightSummaries(
        for wakeDays: [HelmDay],
        records: [SleepRecord],
        calendar: Calendar
    ) -> [HelmDay: SleepNightSummary] {
        let orderedDays = Array(Set(wakeDays)).sorted()
        guard !orderedDays.isEmpty else { return [:] }

        let orderedRecords = records.sorted { $0.start < $1.start }
        var nextRecordIndex = 0
        var activeRecords: [SleepRecord] = []
        var summaries: [HelmDay: SleepNightSummary] = [:]
        summaries.reserveCapacity(orderedDays.count)

        for helmDay in orderedDays {
            guard let wakeDay = calendar.date(from: helmDay.dateComponents()) else { continue }
            let windowStart = sleepWindowStart(for: wakeDay, calendar: calendar)
            let windowEnd = sleepWindowEnd(for: wakeDay, calendar: calendar)

            activeRecords.removeAll { $0.end <= windowStart }
            while nextRecordIndex < orderedRecords.count,
                  orderedRecords[nextRecordIndex].start < windowEnd {
                let record = orderedRecords[nextRecordIndex]
                if record.end > windowStart {
                    activeRecords.append(record)
                }
                nextRecordIndex += 1
            }

            summaries[helmDay] = nightSummary(
                fromRecordsSortedByStart: activeRecords,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
        }

        return summaries
    }

    private static func nightSummary(
        fromRecordsSortedByStart records: [SleepRecord],
        windowStart: Date,
        windowEnd: Date
    ) -> SleepNightSummary {
        var asleepIntervals: [(start: Date, end: Date)] = []
        var inBedIntervals: [(start: Date, end: Date)] = []
        var awakeIntervals: [(start: Date, end: Date)] = []
        var deepIntervals: [(start: Date, end: Date)] = []
        var remIntervals: [(start: Date, end: Date)] = []

        for record in records {
            guard let interval = clip(record.start ... record.end, to: windowStart ... windowEnd) else {
                continue
            }

            switch record.stage {
            case .asleepUnspecified, .asleepCore:
                asleepIntervals.append(interval)
            case .asleepDeep:
                asleepIntervals.append(interval)
                deepIntervals.append(interval)
            case .asleepREM:
                asleepIntervals.append(interval)
                remIntervals.append(interval)
            case .inBed:
                inBedIntervals.append(interval)
            case .awake:
                awakeIntervals.append(interval)
            }
        }

        let asleepMinutes = mergedDurationMinutes(fromSorted: asleepIntervals)
        let inBedMinutes = mergedDurationMinutes(fromSorted: inBedIntervals)
        let awakeMinutes = mergedDurationMinutes(fromSorted: awakeIntervals)
        let deepMinutes = mergedDurationMinutes(fromSorted: deepIntervals)
        let remMinutes = mergedDurationMinutes(fromSorted: remIntervals)

        let asleepHours = asleepMinutes.map { $0 / 60.0 }
        let efficiency = sleepEfficiency(
            asleepMinutes: asleepMinutes,
            inBedMinutes: inBedMinutes,
            awakeMinutes: awakeMinutes
        )

        return SleepNightSummary(
            asleepHours: asleepHours,
            inBedHours: inBedMinutes.map { $0 / 60.0 },
            awakeMinutes: awakeMinutes,
            deepMinutes: deepMinutes,
            remMinutes: remMinutes,
            efficiency: efficiency
        )
    }

    /// Merges overlapping intervals and returns total duration in minutes.
    public static func mergedDurationMinutes(
        from intervals: [(start: Date, end: Date)]
    ) -> Double? {
        let sorted = intervals
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        return mergedDurationMinutes(fromSorted: sorted)
    }

    private static func mergedDurationMinutes(
        fromSorted intervals: [(start: Date, end: Date)]
    ) -> Double? {
        guard !intervals.isEmpty else { return nil }
        var merged: [(start: Date, end: Date)] = []

        for interval in intervals {
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

    private static func sleepEfficiency(
        asleepMinutes: Double?,
        inBedMinutes: Double?,
        awakeMinutes: Double?
    ) -> Double? {
        guard let asleepMinutes, asleepMinutes > 0 else { return nil }
        if let inBedMinutes, inBedMinutes > 0 {
            return min(1.0, asleepMinutes / inBedMinutes)
        }
        if let awakeMinutes {
            let denominator = asleepMinutes + awakeMinutes
            guard denominator > 0 else { return nil }
            return min(1.0, asleepMinutes / denominator)
        }
        return nil
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
