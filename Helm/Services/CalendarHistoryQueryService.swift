import CoachLLM
import Core
import Foundation

/// On-demand calendar event lookups for coach calendar_query.v1.
@MainActor
struct CalendarHistoryQueryService {
    private let hintService: CalendarHintService
    private let calendar: Calendar
    private let cutoff: DayCutoff
    private let weekAheadHorizon: Int

    init(
        hintService: CalendarHintService = CalendarHintBootstrap.service,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default,
        weekAheadHorizon: Int = WeekAheadScheduleBuilder.horizonDays
    ) {
        self.hintService = hintService
        self.calendar = calendar
        self.cutoff = cutoff
        self.weekAheadHorizon = weekAheadHorizon
    }

    func run(_ payload: CalendarQueryPayload, now: Date = Date()) async -> String {
        let status = hintService.currentStatus()
        let statusRaw = status.rawValue
        guard status == .authorized else {
            return CalendarQueryResultFormatter.format(
                query: payload.queryType.rawValue,
                authorizationStatus: statusRaw,
                days: [],
                calendar: calendar
            )
        }

        let today = HelmDay.day(for: now, cutoff: cutoff, calendar: calendar)
        let startDay: HelmDay
        let endDay: HelmDay
        let queryLabel: String

        switch payload.queryType {
        case .today:
            startDay = today
            endDay = today
            queryLabel = "today"
        case .day:
            let day = parseDay(payload.helmDay) ?? today
            startDay = day
            endDay = day
            queryLabel = "day"
        case .range:
            let lookback = min(max(payload.lookbackDays ?? 7, 1), 14)
            endDay = today
            startDay = today.adding(days: -(lookback - 1), calendar: calendar)
            queryLabel = "range"
        case .weekAhead:
            startDay = today
            endDay = today.adding(days: weekAheadHorizon - 1, calendar: calendar)
            queryLabel = "weekAhead"
        }

        let detailsByDay = await hintService.dayDetails(
            from: startDay,
            through: endDay,
            calendar: calendar,
            cutoff: cutoff
        )

        // Include empty days in the requested window so coach can say "nothing on X".
        var days: [CalendarDayDetail] = []
        var cursor = startDay
        while cursor <= endDay {
            if let detail = detailsByDay[cursor] {
                days.append(detail)
            } else {
                days.append(
                    CalendarDayDetail(
                        helmDay: cursor,
                        load: CalendarDayLoad(
                            timedEventCount: 0,
                            scheduledSeconds: 0,
                            hasAllDayEvent: false
                        ),
                        events: []
                    )
                )
            }
            cursor = cursor.adding(days: 1, calendar: calendar)
        }

        var header = queryLabel
        if payload.queryType == .range {
            header = "range lookback=\(min(max(payload.lookbackDays ?? 7, 1), 14))"
        }

        return CalendarQueryResultFormatter.format(
            query: header,
            authorizationStatus: statusRaw,
            days: days,
            calendar: calendar
        )
    }

    private func parseDay(_ raw: String?) -> HelmDay? {
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
}
