import Core
import Foundation
import Persistence
import ReadinessKit

/// Maps persisted health rows into readiness inputs for scoring.
public enum ReadinessHistoryBuilder {
    public static let defaultHistoryDays = 180

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
        _ = calendar
        _ = cutoff

        let metrics = try store.dailyMetrics.fetchRange(from: startDay, through: endDay)
        let metricsByDay = Dictionary(uniqueKeysWithValues: metrics.map { ($0.helmDay, $0) })

        var days = Set(metricsByDay.keys)
        for helmDay in try store.sleep.listDays() where helmDay >= startDay && helmDay <= endDay {
            days.insert(helmDay)
        }

        var history: [ReadinessDayInput] = []
        history.reserveCapacity(days.count)

        for helmDay in days.sorted() {
            let dayMetrics = metricsByDay[helmDay]
            let sleepRecords = try store.sleep.fetch(for: helmDay)
            let sleepDurationHours = totalSleepHours(from: sleepRecords)

            history.append(
                ReadinessDayInput(
                    helmDay: helmDay,
                    hrvDailyAverage: dayMetrics?.hrvSDNN,
                    restingHeartRate: dayMetrics?.restingHeartRate,
                    sleepDurationHours: sleepDurationHours,
                    respiratoryRate: dayMetrics?.respiratoryRate,
                    wristTemperatureDeltaCelsius: dayMetrics?.wristTemperatureDeltaCelsius,
                    priorDayTRIMP: dayMetrics?.priorDayTRIMP
                )
            )
        }

        return history
    }

    private static func totalSleepHours(from records: [SleepRecord]) -> Double? {
        guard !records.isEmpty else { return nil }
        let seconds = records.reduce(0.0) { $0 + $1.duration }
        return seconds / 3_600
    }
}
