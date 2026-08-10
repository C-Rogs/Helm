import Foundation

/// One calendar event retained for coach calendar_query results.
public struct CalendarEventDetail: Sendable, Hashable, Equatable {
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool

    public init(title: String, start: Date, end: Date, isAllDay: Bool) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

/// Summarised calendar load for one logical day.
public struct CalendarDayLoad: Sendable, Hashable, Equatable {
    public let timedEventCount: Int
    public let scheduledSeconds: TimeInterval
    public let hasAllDayEvent: Bool
    /// Titles of all-day events on this day. Empty when hasAllDayEvent is false.
    public let allDayEventTitles: [String]

    public init(
        timedEventCount: Int,
        scheduledSeconds: TimeInterval,
        hasAllDayEvent: Bool,
        allDayEventTitles: [String] = []
    ) {
        self.timedEventCount = timedEventCount
        self.scheduledSeconds = scheduledSeconds
        self.hasAllDayEvent = hasAllDayEvent
        self.allDayEventTitles = allDayEventTitles
    }
}

/// Full day calendar detail for coach lookup (aggregates + event list).
public struct CalendarDayDetail: Sendable, Hashable, Equatable {
    public let helmDay: HelmDay
    public let load: CalendarDayLoad
    public let events: [CalendarEventDetail]

    public init(helmDay: HelmDay, load: CalendarDayLoad, events: [CalendarEventDetail]) {
        self.helmDay = helmDay
        self.load = load
        self.events = events
    }
}

/// Read/write busy-day classification for week-ahead scheduling and coach context.
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

    /// Explains why the engine did or did not mark the day busy (for coach calendar_query).
    public static func engineBusyExplanation(for load: CalendarDayLoad) -> String {
        let scheduledHours = load.scheduledSeconds / 3_600
        let scheduledText = String(format: "%.1f", scheduledHours)
        let thresholdHours = Int(minimumScheduledSeconds / 3_600)
        if load.hasAllDayEvent {
            let titles = load.allDayEventTitles.map { "\"\($0)\"" }.joined(separator: ", ")
            let titlePart = titles.isEmpty ? "" : " titles=\(titles)"
            return "engine_busy=true reason=all_day_event\(titlePart)"
        }
        if load.scheduledSeconds >= minimumScheduledSeconds {
            return "engine_busy=true reason=scheduled_hours>=\(thresholdHours) actual_hours=\(scheduledText)"
        }
        if load.timedEventCount >= minimumTimedEventCount {
            return "engine_busy=true reason=timed_event_count>=\(minimumTimedEventCount) actual=\(load.timedEventCount)"
        }
        return "engine_busy=false reason=below_threshold timed_events=\(load.timedEventCount) scheduled_hours=\(scheduledText) thresholds=events>=\(minimumTimedEventCount)|hours>=\(thresholdHours)|all_day"
    }
}

/// Formats calendar day details into coach tool-result text.
public enum CalendarQueryResultFormatter {
    public static func format(
        query: String,
        authorizationStatus: String,
        days: [CalendarDayDetail],
        calendar: Calendar = .current
    ) -> String {
        var lines = [
            "query=\(query)",
            "calendar_status=\(authorizationStatus)"
        ]
        if authorizationStatus != "authorized" {
            lines.append("error=calendar_unavailable")
            return lines.joined(separator: "\n")
        }
        if days.isEmpty {
            lines.append("events=none")
            return lines.joined(separator: "\n")
        }

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"

        for day in days.sorted(by: { $0.helmDay < $1.helmDay }) {
            let hint = BusyDayHintPolicy.hint(for: day.load) ?? "none"
            lines.append("day=\(day.helmDay.formatted)")
            lines.append("  busy_hint=\(hint)")
            lines.append("  \(BusyDayHintPolicy.engineBusyExplanation(for: day.load))")
            lines.append("  timed_events=\(day.load.timedEventCount) scheduled_hours=\(String(format: "%.1f", day.load.scheduledSeconds / 3_600)) all_day=\(day.load.hasAllDayEvent)")
            if day.events.isEmpty {
                lines.append("  events=none")
                continue
            }
            for event in day.events.sorted(by: { $0.start < $1.start }) {
                let title = event.title.isEmpty ? "(untitled)" : event.title
                if event.isAllDay {
                    lines.append("  event all_day title=\"\(title)\"")
                } else {
                    lines.append(
                        "  event title=\"\(title)\" start=\(timeFormatter.string(from: event.start)) end=\(timeFormatter.string(from: event.end))"
                    )
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// Whether an all-day calendar event should block the entire day for training.
public enum EventBlockingClassification: String, Sendable, Hashable, Equatable, Codable {
    /// The day is fully blocked - session slides to another day.
    case fullyBlocking
    /// The day has an event but a session could still fit (e.g. evening social, morning appointment).
    case partiallyBlocking
}

/// Maps all-day event titles to blocking classifications.
/// Titles are classified by the coach LLM; this enum provides the domain model.
public enum CalendarEventClassifier {
    /// Returns a classification for a set of all-day event titles.
    /// If any title maps to fullyBlocking, the day is fullyBlocking.
    /// Otherwise if any title maps to partiallyBlocking, the day is partiallyBlocking.
    /// When no classifications are known, defaults to fullyBlocking.
    public static func classify(
        titles: [String],
        known: [String: EventBlockingClassification]
    ) -> EventBlockingClassification {
        guard !titles.isEmpty else { return .fullyBlocking }
        let classifications = titles.compactMap { known[$0] }
        if classifications.isEmpty { return .fullyBlocking }
        if classifications.contains(.fullyBlocking) { return .fullyBlocking }
        return .partiallyBlocking
    }

    /// Returns only the days that are fully blocking (sessions should avoid).
    public static func fullyBlockedDays(
        from hints: [HelmDay: String],
        classifications: [HelmDay: EventBlockingClassification]
    ) -> Set<HelmDay> {
        Set(classifications.filter { $0.value == .fullyBlocking }.keys)
    }

    /// Returns days that are partially blocking - sessions stay in play but coach
    /// should negotiate with the athlete.
    public static func partiallyBlockedDays(
        from classifications: [HelmDay: EventBlockingClassification]
    ) -> Set<HelmDay> {
        Set(classifications.filter { $0.value == .partiallyBlocking }.keys)
    }
}
