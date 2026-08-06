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
    func dayLoads(
        from startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar,
        cutoff: DayCutoff
    ) async throws -> [HelmDay: CalendarDayLoad]
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

    func dayLoads(
        from startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar,
        cutoff: DayCutoff
    ) async throws -> [HelmDay: CalendarDayLoad] {
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
        for event in events {
            let helmDay = HelmDay.day(for: event.startDate, cutoff: cutoff, calendar: calendar)
            guard helmDay >= startDay, helmDay <= endDay else { continue }

            var load = loads[helmDay] ?? CalendarDayLoad(
                timedEventCount: 0,
                scheduledSeconds: 0,
                hasAllDayEvent: false
            )

            if event.isAllDay {
                load = CalendarDayLoad(
                    timedEventCount: load.timedEventCount,
                    scheduledSeconds: load.scheduledSeconds,
                    hasAllDayEvent: true
                )
            } else {
                let duration = max(0, event.endDate.timeIntervalSince(event.startDate))
                load = CalendarDayLoad(
                    timedEventCount: load.timedEventCount + 1,
                    scheduledSeconds: load.scheduledSeconds + duration,
                    hasAllDayEvent: load.hasAllDayEvent
                )
            }

            loads[helmDay] = load
        }

        return loads
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

    func busyDayHints(
        from startDay: HelmDay,
        through endDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) async -> [HelmDay: String] {
        guard access.authorizationStatus() == .authorized else {
            return [:]
        }

        do {
            let loads = try await access.dayLoads(
                from: startDay,
                through: endDay,
                calendar: calendar,
                cutoff: cutoff
            )
            return BusyDayHintPolicy.hints(from: loads)
        } catch {
            return [:]
        }
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
}
