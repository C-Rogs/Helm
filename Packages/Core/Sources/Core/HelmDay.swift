import Foundation

/// A logical calendar day keyed off a user-defined local cutoff, not midnight.
public struct HelmDay: Sendable, Hashable, Codable, Comparable, Identifiable {
    public let year: Int
    public let month: Int
    public let day: Int

    public var id: String { formatted }

    public var formatted: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(components: DateComponents) {
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public func dateComponents() -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// Inclusive start of this logical day at the cutoff boundary.
    public func startInstant(cutoff: DayCutoff = .default, calendar: Calendar) -> Date? {
        var components = dateComponents()
        components.hour = cutoff.hour
        components.minute = cutoff.minute
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components)
    }

    /// Exclusive end of this logical day (start of the next logical day).
    public func endInstant(cutoff: DayCutoff = .default, calendar: Calendar) -> Date? {
        guard let start = startInstant(cutoff: cutoff, calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: start)
    }

    /// Whether `instant` falls inside this logical day.
    public func contains(
        _ instant: Date,
        cutoff: DayCutoff = .default,
        calendar: Calendar
    ) -> Bool {
        guard
            let start = startInstant(cutoff: cutoff, calendar: calendar),
            let end = endInstant(cutoff: cutoff, calendar: calendar)
        else {
            return false
        }
        return instant >= start && instant < end
    }

    public static func < (lhs: HelmDay, rhs: HelmDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public extension HelmDay {
    private static var utcGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static let epochFallback = HelmDay(year: 1970, month: 1, day: 1)

    private static func calendarDayFallback(for instant: Date) -> HelmDay {
        let components = utcGregorian.dateComponents([.year, .month, .day], from: instant)
        return HelmDay(components: components) ?? epochFallback
    }

    /// Signed calendar-day distance from this day to `other` (`other` minus `self`).
    func days(to other: HelmDay, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        guard
            let fromDate = calendar.date(from: dateComponents()),
            let toDate = calendar.date(from: other.dateComponents())
        else {
            let fallback = Self.utcGregorian
            guard
                let fromDate = fallback.date(from: dateComponents()),
                let toDate = fallback.date(from: other.dateComponents())
            else {
                return 0
            }
            return fallback.dateComponents([.day], from: fromDate, to: toDate).day ?? 0
        }
        return calendar.dateComponents([.day], from: fromDate, to: toDate).day ?? 0
    }

    /// Canonical logical day for an instant.
    ///
    /// Times before the cutoff on a calendar date belong to the previous logical day.
    /// Example with a 04:00 cutoff: Saturday 03:30 maps to Friday's day.
    static func day(
        for instant: Date,
        cutoff: DayCutoff = .default,
        calendar: Calendar
    ) -> HelmDay {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: instant)
        guard
            let year = dayComponents.year,
            let month = dayComponents.month,
            let day = dayComponents.day
        else {
            return calendarDayFallback(for: instant)
        }

        let cutoffComponents = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: cutoff.hour,
            minute: cutoff.minute,
            second: 0,
            nanosecond: 0
        )

        guard let cutoffInstant = calendar.date(from: cutoffComponents) else {
            return calendarDay(for: instant, calendar: calendar)
        }

        if instant < cutoffInstant {
            guard let previousCalendarDay = calendar.date(byAdding: .day, value: -1, to: cutoffInstant) else {
                return HelmDay(year: year, month: month, day: day)
            }
            let previous = calendar.dateComponents([.year, .month, .day], from: previousCalendarDay)
            return HelmDay(components: previous) ?? HelmDay(year: year, month: month, day: day)
        }

        return HelmDay(year: year, month: month, day: day)
    }

    /// Calendar date for display and week strips (no cutoff shift).
    ///
    /// Use for diary week chips and date pickers. Logging still uses `day(for:)` with cutoff.
    static func calendarDay(for date: Date, calendar: Calendar) -> HelmDay {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return HelmDay(components: components) ?? calendarDayFallback(for: date)
    }

    /// Returns the logical day `days` calendar days before or after this day.
    func adding(days: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> HelmDay {
        let components = dateComponents()
        guard
            let date = calendar.date(from: components),
            let shifted = calendar.date(byAdding: .day, value: days, to: date)
        else {
            let fallback = Self.utcGregorian
            guard
                let date = fallback.date(from: components),
                let shifted = fallback.date(byAdding: .day, value: days, to: date)
            else {
                return self
            }
            let shiftedComponents = fallback.dateComponents([.year, .month, .day], from: shifted)
            return HelmDay(components: shiftedComponents) ?? self
        }
        let shiftedComponents = calendar.dateComponents([.year, .month, .day], from: shifted)
        return HelmDay(components: shiftedComponents) ?? self
    }

    /// The Monday that starts the calendar week containing this day.
    func mondayOfSameWeek(calendar: Calendar = Calendar(identifier: .gregorian)) -> HelmDay {
        guard let date = calendar.date(from: dateComponents()) else { return self }
        let weekday = calendar.component(.weekday, from: date)
        let offset: Int
        switch weekday {
        case 1: offset = -6   // Sunday -> previous Monday
        default: offset = 2 - weekday  // Mon=0, Tue=-1, ..., Sat=-5
        }
        return adding(days: offset, calendar: calendar)
    }

    /// Short weekday name ("Mon") using the current calendar. Cached formatter.
    @MainActor
    public var shortWeekday: String {
        guard let date = Calendar.current.date(from: dateComponents()) else { return "?" }
        return HelmDayFormatters.weekday.string(from: date)
    }

    /// Compact display label ("Mon 4 Aug") using the current calendar. Cached formatter.
    @MainActor
    public var formattedLabel: String {
        guard let date = Calendar.current.date(from: dateComponents()) else { return formatted }
        return HelmDayFormatters.dayMonth.string(from: date)
    }
}

/// Cached `DateFormatter`s for `HelmDay` display labels. DateFormatter is not Sendable;
/// access is confined to the main actor where all label rendering happens.
@MainActor
enum HelmDayFormatters {
    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    static let dayMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()
}
