import Core
import Foundation

public enum PlannedSessionWindowEstimator {
    public static let defaultHour = 17
    public static let defaultMinute = 0
    public static let preWorkoutLeadMinutes = 30
    public static let historyLookback = 12

    public static func plannedStart(
        for day: HelmDay,
        recentSessions: [WorkoutSessionSummary],
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) -> Date? {
        guard let dayStart = day.startInstant(cutoff: cutoff, calendar: calendar) else {
            return nil
        }

        let targetWeekday = calendar.component(.weekday, from: dayStart)
        let sameWeekdaySessions = recentSessions
            .filter { calendar.component(.weekday, from: $0.startedAt) == targetWeekday }
            .prefix(historyLookback)

        let minutesSinceMidnight: [Int]
        if sameWeekdaySessions.isEmpty {
            minutesSinceMidnight = [defaultHour * 60 + defaultMinute]
        } else {
            minutesSinceMidnight = sameWeekdaySessions.map { session in
                let components = calendar.dateComponents([.hour, .minute], from: session.startedAt)
                return (components.hour ?? defaultHour) * 60 + (components.minute ?? defaultMinute)
            }
        }

        let medianMinutes = median(minutesSinceMidnight)
        let hour = medianMinutes / 60
        let minute = medianMinutes % 60

        var components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    public static func preWorkoutFireDate(
        plannedStart: Date,
        leadMinutes: Int = preWorkoutLeadMinutes
    ) -> Date {
        plannedStart.addingTimeInterval(TimeInterval(-leadMinutes * 60))
    }

    public static func shouldSchedulePreWorkout(
        fireDate: Date,
        now: Date,
        workoutCompletedToday: Bool
    ) -> Bool {
        guard !workoutCompletedToday else { return false }
        return fireDate > now
    }

    public static func fireInterval(fireDate: Date, now: Date) -> TimeInterval? {
        let interval = fireDate.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        return interval
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return defaultHour * 60 + defaultMinute }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
