import Foundation

/// Resolves `calendar_query` windows and title search. Engine week-ahead busy stays separate.
public enum CalendarQueryWindowKind: String, Sendable, Equatable {
    case today
    case day
    case range
    case weekAhead
}

public enum CalendarQueryPlanner: Sendable {
    public static let maxLookbackDays = 14
    public static let maxLookaheadDays = 365
    public static let defaultSearchLookaheadDays = 365

    public struct ResolvedWindow: Sendable, Equatable {
        public let startDay: HelmDay
        public let endDay: HelmDay
        public let queryLabel: String
        public let search: String?
        public let omitEmptyDays: Bool
    }

    public static func normalizedSearch(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    public static func parseHelmDay(_ raw: String?) -> HelmDay? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }

    public static func titleMatches(_ title: String, search: String) -> Bool {
        title.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    public static func eventMatches(_ event: CalendarEventDetail, search: String) -> Bool {
        titleMatches(event.title, search: search)
            || titleMatches(event.location, search: search)
            || titleMatches(event.notes, search: search)
    }

    public static func applySearch(_ days: [CalendarDayDetail], search: String?) -> [CalendarDayDetail] {
        guard let search else { return days }
        return days.compactMap { day in
            let matched = day.events.filter { eventMatches($0, search: search) }
            guard !matched.isEmpty else { return nil }
            return CalendarDayDetail(
                helmDay: day.helmDay,
                load: CalendarDayLoad.from(events: matched),
                events: matched
            )
        }
    }

    public static func resolve(
        kind: CalendarQueryWindowKind,
        today: HelmDay,
        helmDay: String? = nil,
        lookbackDays: Int? = nil,
        lookaheadDays: Int? = nil,
        search: String? = nil,
        weekAheadHorizon: Int,
        calendar: Calendar = .current
    ) -> ResolvedWindow {
        let search = normalizedSearch(search)
        switch kind {
        case .today:
            if let search {
                return namedSearchWindow(
                    today: today,
                    kindLabel: "today",
                    search: search,
                    lookbackDays: lookbackDays,
                    lookaheadDays: lookaheadDays,
                    calendar: calendar
                )
            }
            return ResolvedWindow(
                startDay: today,
                endDay: today,
                queryLabel: "today",
                search: nil,
                omitEmptyDays: false
            )
        case .day:
            if let search, parseHelmDay(helmDay) == nil {
                return namedSearchWindow(
                    today: today,
                    kindLabel: "day",
                    search: search,
                    lookbackDays: lookbackDays,
                    lookaheadDays: lookaheadDays,
                    calendar: calendar
                )
            }
            let day = parseHelmDay(helmDay) ?? today
            return ResolvedWindow(
                startDay: day,
                endDay: day,
                queryLabel: queryLabel(kind: "day", search: search, lookback: nil, lookahead: nil),
                search: search,
                omitEmptyDays: search != nil
            )
        case .range:
            if let search {
                return namedSearchWindow(
                    today: today,
                    kindLabel: "range",
                    search: search,
                    lookbackDays: lookbackDays,
                    lookaheadDays: lookaheadDays,
                    calendar: calendar
                )
            }
            if let lookaheadDays {
                let back = clamp(lookbackDays ?? 1, min: 1, max: maxLookbackDays)
                let ahead = clamp(lookaheadDays, min: 1, max: maxLookaheadDays)
                let startDay = today.adding(days: -(back - 1), calendar: calendar)
                let endDay = today.adding(days: ahead - 1, calendar: calendar)
                return ResolvedWindow(
                    startDay: startDay,
                    endDay: endDay,
                    queryLabel: queryLabel(kind: "range", search: nil, lookback: back, lookahead: ahead),
                    search: nil,
                    omitEmptyDays: spanDays(from: startDay, through: endDay, calendar: calendar) > 7
                )
            }
            let lookback = clamp(lookbackDays ?? 7, min: 1, max: maxLookbackDays)
            return ResolvedWindow(
                startDay: today.adding(days: -(lookback - 1), calendar: calendar),
                endDay: today,
                queryLabel: "range lookback=\(lookback)",
                search: nil,
                omitEmptyDays: false
            )
        case .weekAhead:
            if let search {
                return namedSearchWindow(
                    today: today,
                    kindLabel: "weekAhead",
                    search: search,
                    lookbackDays: lookbackDays,
                    lookaheadDays: lookaheadDays,
                    calendar: calendar
                )
            }
            let horizon = max(weekAheadHorizon, 1)
            return ResolvedWindow(
                startDay: today,
                endDay: today.adding(days: horizon - 1, calendar: calendar),
                queryLabel: "weekAhead",
                search: nil,
                omitEmptyDays: false
            )
        }
    }

    private static func namedSearchWindow(
        today: HelmDay,
        kindLabel: String,
        search: String,
        lookbackDays: Int?,
        lookaheadDays: Int?,
        calendar: Calendar
    ) -> ResolvedWindow {
        let back = clamp(lookbackDays ?? 0, min: 0, max: maxLookbackDays)
        let ahead = clamp(lookaheadDays ?? defaultSearchLookaheadDays, min: 1, max: maxLookaheadDays)
        let startDay = today.adding(days: -max(back - 1, 0), calendar: calendar)
        let endDay = today.adding(days: ahead - 1, calendar: calendar)
        return ResolvedWindow(
            startDay: startDay,
            endDay: endDay,
            queryLabel: queryLabel(
                kind: kindLabel,
                search: search,
                lookback: back == 0 ? nil : back,
                lookahead: ahead
            ),
            search: search,
            omitEmptyDays: true
        )
    }

    private static func clamp(_ value: Int, min minValue: Int, max maxValue: Int) -> Int {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private static func spanDays(from start: HelmDay, through end: HelmDay, calendar: Calendar) -> Int {
        var count = 1
        var cursor = start
        while cursor < end {
            cursor = cursor.adding(days: 1, calendar: calendar)
            count += 1
            if count > 400 {
                break
            }
        }
        return count
    }

    private static func queryLabel(kind: String, search: String?, lookback: Int?, lookahead: Int?) -> String {
        var parts = [kind]
        if let search {
            let safe = search.replacingOccurrences(of: "\"", with: "'")
            parts.append("search=\"\(safe)\"")
        }
        if let lookback {
            parts.append("lookback=\(lookback)")
        }
        if let lookahead {
            parts.append("lookahead=\(lookahead)")
        }
        return parts.joined(separator: " ")
    }
}
