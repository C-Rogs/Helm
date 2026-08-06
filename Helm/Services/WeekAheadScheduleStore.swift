import Core
import DesignSystem
import Foundation
import HealthKitIngest
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
    private let prescriptionService: PrescriptionService
    private let calendar: Calendar
    private let cutoff: DayCutoff

    init(
        store: PersistenceStore,
        calendarHintService: CalendarHintService = CalendarHintBootstrap.service,
        prescriptionService: PrescriptionService = PlanBootstrap.prescriptionService,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.store = store
        self.calendarHintService = calendarHintService
        self.prescriptionService = prescriptionService
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
            let busyDayHints = await calendarHintService.busyDayHints(
                from: today,
                through: endDay,
                calendar: calendar,
                cutoff: cutoff
            )
            let busyDays = Set(busyDayHints.keys)
            let readiness = ReadinessBootstrap.readinessService.state.score
            await prescriptionService.refresh(readiness: readiness, busyDays: busyDays)

            model = try WeekAheadScheduleBuilder.build(
                store: store,
                today: today,
                calendar: calendar,
                cutoff: cutoff,
                busyDayHints: busyDayHints
            )
        } catch {
            model = WeekAheadScheduleModel(rows: [])
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func requestCalendarAccess() async {
        calendarAuthorizationStatus = await calendarHintService.requestAccess()
        await refresh()
    }
}

enum WeekAheadScheduleBootstrap {
    @MainActor
    static let store = WeekAheadScheduleStore(store: PersistenceBootstrap.persistenceStore)
}
