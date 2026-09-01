import Core
import Foundation

/// When to nudge an empty usual-meal bucket. Learned from log times; suppressed outside a meal window.
public enum UsualMealFirePlanner {
    public static let afterTypicalMinutes = 15
    public static let overdueLeadSeconds: TimeInterval = 20

    public static func defaultMinutesSinceMidnight(for bucket: MealBucket) -> Int {
        switch bucket {
        case .breakfast: 9 * 60
        case .lunch: 13 * 60
        case .dinner: 19 * 60
        case .snacks: 16 * 60
        }
    }

    public static func windowEndMinutesSinceMidnight(for bucket: MealBucket) -> Int {
        switch bucket {
        case .breakfast: 11 * 60 + 30
        case .lunch: 16 * 60
        case .dinner: 21 * 60 + 30
        case .snacks: 20 * 60
        }
    }

    public static func typicalMinutesSinceMidnight(
        sampleLoggedAts: [Date],
        bucket: MealBucket,
        calendar: Calendar = .current
    ) -> Int {
        let minutes = sampleLoggedAts.map { date in
            calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        }
        guard !minutes.isEmpty else {
            return defaultMinutesSinceMidnight(for: bucket)
        }
        return min(
            median(minutes) + afterTypicalMinutes,
            windowEndMinutesSinceMidnight(for: bucket)
        )
    }

    public static func fireDate(
        day: HelmDay,
        bucket: MealBucket,
        sampleLoggedAts: [Date],
        now: Date,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) -> Date? {
        guard let windowEnd = clockDate(
            day: day,
            minutesSinceMidnight: windowEndMinutesSinceMidnight(for: bucket),
            calendar: calendar,
            cutoff: cutoff
        ) else {
            return nil
        }
        guard now <= windowEnd else { return nil }

        let typical = typicalMinutesSinceMidnight(
            sampleLoggedAts: sampleLoggedAts,
            bucket: bucket,
            calendar: calendar
        )
        guard var fire = clockDate(
            day: day,
            minutesSinceMidnight: typical,
            calendar: calendar,
            cutoff: cutoff
        ) else {
            return nil
        }
        if fire > windowEnd {
            fire = windowEnd
        }
        if fire <= now {
            return now.addingTimeInterval(overdueLeadSeconds)
        }
        return fire
    }

    public static func fireInterval(fireDate: Date, now: Date) -> TimeInterval? {
        let interval = fireDate.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        return interval
    }

    private static func clockDate(
        day: HelmDay,
        minutesSinceMidnight: Int,
        calendar: Calendar,
        cutoff: DayCutoff
    ) -> Date? {
        guard let dayStart = day.startInstant(cutoff: cutoff, calendar: calendar) else {
            return nil
        }
        var components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        components.hour = minutesSinceMidnight / 60
        components.minute = minutesSinceMidnight % 60
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components)
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
