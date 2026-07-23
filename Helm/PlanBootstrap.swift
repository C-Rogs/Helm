import Foundation
import HealthKitIngest
import Persistence

enum PlanBootstrap {
    private static let engine = PlanPrescriptionEngine(persistence: PersistenceBootstrap.persistenceStore)

    @MainActor
    static let prescriptionService = PrescriptionService(engine: engine)

    @MainActor
    static func start() {
        Task(priority: .userInitiated) {
            let readiness = ReadinessBootstrap.readinessService.state.score
            await prescriptionService.refresh(readiness: readiness)
        }
    }

    @MainActor
    static func refreshPrescription() {
        Task {
            let readiness = ReadinessBootstrap.readinessService.state.score
            await prescriptionService.refresh(readiness: readiness)
        }
    }
}
