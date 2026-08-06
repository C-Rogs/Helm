import Core
import Foundation
import HealthKitIngest
import Persistence

enum PlanBootstrap {
    static let engine = PlanPrescriptionEngine(persistence: PersistenceBootstrap.persistenceStore)

    @MainActor
    static let prescriptionService = PrescriptionService(engine: engine)

    @MainActor
    static func start() {
        Task(priority: .userInitiated) {
            await refreshPrescriptionWithCalendar()
            await ProactiveBootstrap.refreshScheduling()
        }
    }

    @MainActor
    static func refreshPrescription() {
        Task {
            await refreshPrescriptionWithCalendar()
            await ProactiveBootstrap.refreshScheduling()
        }
    }

    @MainActor
    static func refreshPrescriptionWithCalendar() async {
        let today = HelmDay.day(for: .now, cutoff: .default, calendar: .current)
        let endDay = today.adding(days: WeekAheadScheduleBuilder.horizonDays - 1)
        let busyDays = await CalendarHintBootstrap.service.busyDays(from: today, through: endDay)
        let readiness = ReadinessBootstrap.readinessService.state.score
        await prescriptionService.refresh(readiness: readiness, busyDays: busyDays)
    }
}
