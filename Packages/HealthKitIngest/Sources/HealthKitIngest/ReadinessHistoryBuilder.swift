import Core
import Diagnostics
import Foundation
import Persistence
import ReadinessKit

/// Maps persisted health rows into readiness inputs for scoring.
public enum ReadinessHistoryBuilder {
    /// Scoring windows need up to 14 days of history (HRV acute/medium, sleep debt).
    /// 30 days provides a buffer while keeping queries fast.
    public static let defaultHistoryDays = 30

    private static let historySignpost = HelmSignpost(
        name: .readinessHistoryBuild,
        category: .healthKitIngest
    )

    public static func history(
        from store: PersistenceStore,
        endingAt endDay: HelmDay,
        lookbackDays: Int = defaultHistoryDays,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> [ReadinessDayInput] {
        let startDay = endDay.adding(days: -(lookbackDays - 1), calendar: calendar)
        return try history(from: store, from: startDay, through: endDay, calendar: calendar, cutoff: cutoff)
    }

    public static func history(
        from store: PersistenceStore,
        window: BackfillWindow,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> [ReadinessDayInput] {
        let startDay = HelmDay.day(for: window.start, cutoff: cutoff, calendar: calendar)
        let endDay = HelmDay.day(for: window.end, cutoff: cutoff, calendar: calendar)
        return try history(from: store, from: startDay, through: endDay, calendar: calendar, cutoff: cutoff)
    }

    public static func history(
        from store: PersistenceStore,
        from startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> [ReadinessDayInput] {
        let signpostID = historySignpost.makeSignpostID()
        historySignpost.begin(id: signpostID)
        defer { historySignpost.end(id: signpostID) }

        _ = calendar
        _ = cutoff

        let metrics = try store.dailyMetrics.fetchRange(from: startDay, through: endDay)
        let metricsByDay = Dictionary(uniqueKeysWithValues: metrics.map { ($0.helmDay, $0) })

        // Wake-day sleep windows: every calendar day in range, not only days that
        // already have a metrics row or an onset-bucketed sleep_record helm_day.
        var days = Set<HelmDay>()
        var cursor = startDay
        while cursor <= endDay {
            days.insert(cursor)
            cursor = cursor.adding(days: 1, calendar: calendar)
        }
        for helmDay in try store.sleep.listDays() where helmDay >= startDay && helmDay <= endDay {
            days.insert(helmDay)
        }

        let historyWindowStart = sleepHistoryWindowStart(for: startDay, calendar: calendar)
        let historyWindowEnd = sleepHistoryWindowEnd(for: endDay, calendar: calendar)
        let sleepRecords = try store.sleep.fetchOverlapping(
            start: historyWindowStart,
            end: historyWindowEnd
        )

        var history: [ReadinessDayInput] = []
        history.reserveCapacity(days.count)

        for helmDay in days.sorted() {
            let dayMetrics = metricsByDay[helmDay]
            guard let wakeDay = calendar.date(from: helmDay.dateComponents()) else { continue }
            let windowStart = SleepAggregation.sleepWindowStart(for: wakeDay, calendar: calendar)
            let windowEnd = SleepAggregation.sleepWindowEnd(for: wakeDay, calendar: calendar)
            let nightRecords = sleepRecords.filter { $0.end > windowStart && $0.start < windowEnd }
            let nightSummary = SleepAggregation.nightSummary(
                from: nightRecords,
                windowStart: windowStart,
                windowEnd: windowEnd
            )

            history.append(
                ReadinessDayInput(
                    helmDay: helmDay,
                    hrvDailyAverage: dayMetrics?.hrvSDNN,
                    restingHeartRate: resolvedRestingHeartRate(
                        for: helmDay,
                        dayMetrics: dayMetrics,
                        metricsByDay: metricsByDay,
                        calendar: calendar
                    ),
                    sleepDurationHours: nightSummary.asleepHours,
                    sleepEfficiency: nightSummary.efficiency,
                    deepSleepMinutes: nightSummary.deepMinutes,
                    remSleepMinutes: nightSummary.remMinutes,
                    respiratoryRate: dayMetrics?.respiratoryRate,
                    wristTemperatureDeltaCelsius: dayMetrics?.wristTemperatureDeltaCelsius,
                    priorDayTRIMP: dayMetrics?.priorDayTRIMP
                )
            )
        }

        return history
    }

    /// When today's bucket is empty, use yesterday's stored RHR (overnight reading Health shows as today).
    private static func resolvedRestingHeartRate(
        for helmDay: HelmDay,
        dayMetrics: DailyMetrics?,
        metricsByDay: [HelmDay: DailyMetrics],
        calendar: Calendar
    ) -> Int? {
        if let restingHeartRate = dayMetrics?.restingHeartRate {
            return restingHeartRate
        }
        let priorDay = helmDay.adding(days: -1, calendar: calendar)
        return metricsByDay[priorDay]?.restingHeartRate
    }

    private static func sleepHistoryWindowStart(for startDay: HelmDay, calendar: Calendar) -> Date {
        guard let wakeDay = calendar.date(from: startDay.dateComponents()) else {
            preconditionFailure("calendar could not build wake day for \(startDay.formatted)")
        }
        return SleepAggregation.sleepWindowStart(for: wakeDay, calendar: calendar)
    }

    private static func sleepHistoryWindowEnd(for endDay: HelmDay, calendar: Calendar) -> Date {
        guard let wakeDay = calendar.date(from: endDay.dateComponents()) else {
            preconditionFailure("calendar could not build wake day for \(endDay.formatted)")
        }
        return SleepAggregation.sleepWindowEnd(for: wakeDay, calendar: calendar)
    }
}
