import Foundation

/// Summarised calendar load for one logical day.
public struct CalendarDayLoad: Sendable, Hashable, Equatable {
    public let timedEventCount: Int
    public let scheduledSeconds: TimeInterval
    public let hasAllDayEvent: Bool

    public init(
        timedEventCount: Int,
        scheduledSeconds: TimeInterval,
        hasAllDayEvent: Bool
    ) {
        self.timedEventCount = timedEventCount
        self.scheduledSeconds = scheduledSeconds
        self.hasAllDayEvent = hasAllDayEvent
    }
}

/// Read-only busy-day classification for week-ahead hints.
public enum BusyDayHintPolicy {
    public static let minimumScheduledSeconds: TimeInterval = 4 * 3_600
    public static let minimumTimedEventCount = 3

    public static func hint(for load: CalendarDayLoad) -> String? {
        if load.hasAllDayEvent {
            return "Busy day"
        }

        if load.scheduledSeconds >= minimumScheduledSeconds {
            let hours = Int((load.scheduledSeconds / 3_600).rounded())
            return "Busy · \(hours)h scheduled"
        }

        if load.timedEventCount >= minimumTimedEventCount {
            return "Busy · \(load.timedEventCount) events"
        }

        return nil
    }

    public static func hints(from loads: [HelmDay: CalendarDayLoad]) -> [HelmDay: String] {
        loads.compactMapValues(hint(for:))
    }
}
