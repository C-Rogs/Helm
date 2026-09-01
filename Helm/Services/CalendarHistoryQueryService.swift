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
        let today = HelmDay.day(for: now, cutoff: cutoff, calendar: calendar)
        let kind = CalendarQueryWindowKind(rawValue: payload.queryType.rawValue) ?? .today
        let window = CalendarQueryPlanner.resolve(
            kind: kind,
            today: today,
            helmDay: payload.helmDay,
            lookbackDays: payload.lookbackDays,
            lookaheadDays: payload.lookaheadDays,
            search: payload.search,
            weekAheadHorizon: weekAheadHorizon,
            calendar: calendar
        )

        guard status == .authorized else {
            return CalendarQueryResultFormatter.format(
                query: window.queryLabel,
                authorizationStatus: statusRaw,
                days: [],
                calendar: calendar
            )
        }

        let detailsByDay = await hintService.dayDetails(
            from: window.startDay,
            through: window.endDay,
            calendar: calendar,
            cutoff: cutoff
        )

        var days: [CalendarDayDetail] = []
        if window.omitEmptyDays {
            days = detailsByDay.values.sorted { $0.helmDay < $1.helmDay }
        } else {
            // Include empty days in short windows so coach can say "nothing on X".
            var cursor = window.startDay
            while cursor <= window.endDay {
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
        }

        days = CalendarQueryPlanner.applySearch(days, search: window.search)

        return CalendarQueryResultFormatter.format(
            query: window.queryLabel,
            authorizationStatus: statusRaw,
            days: days,
            calendar: calendar
        )
    }
}
