import Core
@preconcurrency import EventKit
import Foundation

enum CalendarAuthorizationStatus: String, Equatable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

@MainActor
protocol CalendarEventAccessProviding {
    func authorizationStatus() -> CalendarAuthorizationStatus
    func requestAccess() async -> CalendarAuthorizationStatus
    func dayDetails(
        from startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar,
        cutoff: DayCutoff
    ) async throws -> [HelmDay: CalendarDayDetail]
}

@MainActor
final class LiveCalendarEventAccess: CalendarEventAccessProviding {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func authorizationStatus() -> CalendarAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess, .authorized:
            return .authorized
        case .writeOnly:
            return .denied
        @unknown default:
            return .denied
        }
    }

    func requestAccess() async -> CalendarAuthorizationStatus {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            return granted ? .authorized : .denied
        } catch {
            return authorizationStatus()
        }
    }

    func dayDetails(
        from startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar,
        cutoff: DayCutoff
    ) async throws -> [HelmDay: CalendarDayDetail] {
        guard authorizationStatus() == .authorized else {
            return [:]
        }

        guard
            let rangeStart = startDay.startInstant(cutoff: cutoff, calendar: calendar),
            let rangeEnd = endDay.endInstant(cutoff: cutoff, calendar: calendar)
        else {
            return [:]
        }

        let predicate = eventStore.predicateForEvents(
            withStart: rangeStart,
            end: rangeEnd,
            calendars: nil
        )
        let events = eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }

        var loads: [HelmDay: CalendarDayLoad] = [:]
        var eventLists: [HelmDay: [CalendarEventDetail]] = [:]
        for event in events {
            let helmDay: HelmDay
            if event.isAllDay {
                // All-day events start at midnight; the 04:00 cutoff would
                // shift them to the previous logical day. Use calendar day.
                helmDay = HelmDay.calendarDay(for: event.startDate, calendar: calendar)
            } else {
                helmDay = HelmDay.day(for: event.startDate, cutoff: cutoff, calendar: calendar)
            }
            guard helmDay >= startDay, helmDay <= endDay else { continue }

            var load = loads[helmDay] ?? CalendarDayLoad(
                timedEventCount: 0,
                scheduledSeconds: 0,
                hasAllDayEvent: false
            )
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if event.isAllDay {
                var titles = load.allDayEventTitles
                if !title.isEmpty {
                    titles.append(title)
                }
                load = CalendarDayLoad(
                    timedEventCount: load.timedEventCount,
                    scheduledSeconds: load.scheduledSeconds,
                    hasAllDayEvent: true,
                    allDayEventTitles: titles
                )
            } else {
                let duration = max(0, event.endDate.timeIntervalSince(event.startDate))
                load = CalendarDayLoad(
                    timedEventCount: load.timedEventCount + 1,
                    scheduledSeconds: load.scheduledSeconds + duration,
                    hasAllDayEvent: load.hasAllDayEvent,
                    allDayEventTitles: load.allDayEventTitles
                )
            }

            loads[helmDay] = load
            var list = eventLists[helmDay] ?? []
            list.append(
                CalendarEventDetail(
                    title: title,
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay
                )
            )
            eventLists[helmDay] = list
        }

        return Dictionary(uniqueKeysWithValues: loads.map { day, load in
            (
                day,
                CalendarDayDetail(
                    helmDay: day,
                    load: load,
                    events: eventLists[day] ?? []
                )
            )
        })
    }
}

@MainActor
final class CalendarHintService {
    private let access: any CalendarEventAccessProviding

    init(access: (any CalendarEventAccessProviding)? = nil) {
        self.access = access ?? LiveCalendarEventAccess()
    }

    func currentStatus() -> CalendarAuthorizationStatus {
        access.authorizationStatus()
    }

    func requestAccess() async -> CalendarAuthorizationStatus {
        await access.requestAccess()
    }

    func dayDetails(
        from startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) async -> [HelmDay: CalendarDayDetail] {
        guard access.authorizationStatus() == .authorized else {
            return [:]
        }

        do {
            return try await access.dayDetails(
                from: startDay,
                through: endDay,
                calendar: calendar,
                cutoff: cutoff
            )
        } catch {
            return [:]
        }
    }

    func dayLoads(
        from startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) async -> [HelmDay: CalendarDayLoad] {
        await dayDetails(from: startDay, through: endDay, calendar: calendar, cutoff: cutoff)
            .mapValues(\.load)
    }

    func busyDayHints(
        from startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) async -> [HelmDay: String] {
        BusyDayHintPolicy.hints(
            from: await dayLoads(
                from: startDay,
                through: endDay,
                calendar: calendar,
                cutoff: cutoff
            )
        )
    }

    func busyDays(
        from startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) async -> Set<HelmDay> {
        Set(
            await busyDayHints(
                from: startDay,
                through: endDay,
                calendar: calendar,
                cutoff: cutoff
            ).keys
        )
    }
}

enum CalendarHintBootstrap {
    @MainActor
    static let service = CalendarHintService()
    @MainActor
    static let eventClassifier = CalendarEventClassifierService()
}
