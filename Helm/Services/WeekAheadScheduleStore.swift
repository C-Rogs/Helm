import Core
import DesignSystem
import Foundation
import Observation
import Persistence

@Observable
@MainActor
final class WeekAheadScheduleStore {
    private(set) var model: WeekAheadScheduleModel?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var calendarAuthorizationStatus = CalendarAuthorizationStatus.notDetermined

    private let store: PersistenceStore
    private let calendarHintService: CalendarHintService
    private let calendar: Calendar
    private let cutoff: DayCutoff

    init(
        store: PersistenceStore,
        calendarHintService: CalendarHintService = CalendarHintBootstrap.service,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.store = store
        self.calendarHintService = calendarHintService
        self.calendar = calendar
        self.cutoff = cutoff
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        calendarAuthorizationStatus = calendarHintService.currentStatus()

        do {
            let today = HelmDay.day(for: .now, cutoff: cutoff, calendar: calendar)
            let endDay = today.adding(days: WeekAheadScheduleBuilder.horizonDays - 1, calendar: calendar)

            let loads = await calendarHintService.dayLoads(
                from: today,
                through: endDay,
                calendar: calendar,
                cutoff: cutoff
            )
            let classifications = await CalendarHintBootstrap.eventClassifier.classify(
                loads: loads
            )
            let fullyBlocked = CalendarEventClassifier.fullyBlockedDays(
                from: [:],
                classifications: classifications
            )
            let partiallyBlocked = CalendarEventClassifier.partiallyBlockedDays(
                from: classifications
            )

            let busyDayHints = buildBusyDayHints(
                loads: loads,
                classifications: classifications,
                fullyBlocked: fullyBlocked,
                partiallyBlocked: partiallyBlocked
            )

            model = try WeekAheadScheduleBuilder.build(
                store: store,
                today: today,
                calendar: calendar,
                cutoff: cutoff,
                busyDayHints: busyDayHints,
                partiallyBlockedDays: partiallyBlocked
            )
        } catch {
            model = WeekAheadScheduleModel(rows: [])
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func buildBusyDayHints(
        loads: [HelmDay: CalendarDayLoad],
        classifications: [HelmDay: EventBlockingClassification],
        fullyBlocked: Set<HelmDay>,
        partiallyBlocked: Set<HelmDay>
    ) -> [HelmDay: String] {
        var hints: [HelmDay: String] = [:]

        for (helmDay, load) in loads {
            if fullyBlocked.contains(helmDay) {
                hints[helmDay] = "Busy day"
            } else if partiallyBlocked.contains(helmDay) {
                let titles = load.allDayEventTitles.map { "\"\($0)\"" }.joined(separator: ", ")
                hints[helmDay] = "Busy (PM) - \(titles)"
            } else if let hint = BusyDayHintPolicy.hint(for: load) {
                hints[helmDay] = hint
            }
        }

        return hints
    }

    func requestCalendarAccess() async {
        let prior = calendarAuthorizationStatus
        calendarAuthorizationStatus = await calendarHintService.requestAccess()
        if prior != .authorized, calendarAuthorizationStatus == .authorized {
            await PlanBootstrap.refreshPrescriptionWithCalendar()
        }
        await refresh()
    }
}

enum WeekAheadScheduleBootstrap {
    @MainActor
    static let store = WeekAheadScheduleStore(store: PersistenceBootstrap.persistenceStore)
}
