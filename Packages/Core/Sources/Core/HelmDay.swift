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
            preconditionFailure("calendar could not extract year/month/day")
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
            preconditionFailure("calendar could not build cutoff instant")
        }

        if instant < cutoffInstant {
            guard
                let previousCalendarDay = calendar.date(byAdding: .day, value: -1, to: cutoffInstant)
            else {
                preconditionFailure("calendar could not step back one day")
            }
            let previous = calendar.dateComponents([.year, .month, .day], from: previousCalendarDay)
            guard let helmDay = HelmDay(components: previous) else {
                preconditionFailure("calendar produced incomplete day components")
            }
            return helmDay
        }

        return HelmDay(year: year, month: month, day: day)
    }
}
