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
        let asleepStages: Set<SleepAnalysisStage> = [
            .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM
        ]

        let asleepMinutes = mergedDurationMinutes(
            from: records,
            stages: asleepStages,
            windowStart: windowStart,
            windowEnd: windowEnd
        )
        let inBedMinutes = mergedDurationMinutes(
            from: records,
            stages: [.inBed],
            windowStart: windowStart,
            windowEnd: windowEnd
        )
        let awakeMinutes = mergedDurationMinutes(
            from: records,
            stages: [.awake],
            windowStart: windowStart,
            windowEnd: windowEnd
        )
        let deepMinutes = mergedDurationMinutes(
            from: records,
            stages: [.asleepDeep],
            windowStart: windowStart,
            windowEnd: windowEnd
        )
        let remMinutes = mergedDurationMinutes(
            from: records,
            stages: [.asleepREM],
            windowStart: windowStart,
            windowEnd: windowEnd
        )

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

    private static func mergedDurationMinutes(
        from records: [SleepRecord],
        stages: Set<SleepAnalysisStage>,
        windowStart: Date,
        windowEnd: Date
    ) -> Double? {
        let intervals = records.compactMap { record -> (start: Date, end: Date)? in
            guard stages.contains(record.stage) else { return nil }
            return clip(record.start ... record.end, to: windowStart ... windowEnd)
        }
        return mergedDurationMinutes(from: intervals)
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
