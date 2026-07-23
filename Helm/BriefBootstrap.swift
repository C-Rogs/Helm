import Foundation
import HealthKitIngest
import Persistence

enum BriefBootstrap {
    private static let engine = BriefEngine(
        persistence: PersistenceBootstrap.persistenceStore,
        prescriptionEngine: PlanBootstrap.engine
    )

    @MainActor
    static let briefService = BriefService(engine: engine)

    @MainActor
    static func start() {
        Task(priority: .userInitiated) {
            await refreshBrief()
        }
    }

    @MainActor
    static func refreshBrief(attemptNarration: Bool = true) {
        Task {
            let readiness = ReadinessBootstrap.readinessService.state.score
            let summary = PlanBootstrap.prescriptionService.state.summary
            await briefService.refresh(
                readiness: readiness,
                prescriptionSummary: summary,
                attemptNarration: attemptNarration
            )
        }
    }
}
