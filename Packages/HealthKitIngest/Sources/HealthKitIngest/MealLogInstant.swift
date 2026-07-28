import Core
import Foundation

public enum MealLogInstant {
    /// When logging on today, use the current clock time. On past diary days, anchor to a typical meal time.
    public static func loggedAt(
        for helmDay: HelmDay,
        bucket: MealBucket,
        today: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default,
        now: Date = Date()
    ) -> Date {
        guard helmDay != today else {
            return now
        }

        let hourOffset: Int = switch bucket {
        case .breakfast: 8
        case .lunch: 12
        case .dinner: 18
        case .snacks: 15
        }

        guard let start = helmDay.startInstant(cutoff: cutoff, calendar: calendar) else {
            return now
        }
        return calendar.date(byAdding: .hour, value: hourOffset, to: start) ?? now
    }
}
