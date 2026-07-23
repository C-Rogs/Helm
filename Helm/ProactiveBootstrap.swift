import Foundation
import HealthKitIngest
import Persistence

enum ProactiveBootstrap {
    private static let persistence = PersistenceBootstrap.persistenceStore

    @MainActor
    static let notificationScheduler = ProactiveNotificationScheduler(persistence: persistence)

    @MainActor
    static let thresholdInsightService = ThresholdInsightService(persistence: persistence)

    @MainActor
    static func start() {
        Task {
            await refreshScheduling()
            await refreshThresholdInsights()
        }
    }

    @MainActor
    static func refreshScheduling() async {
        let readiness = ReadinessBootstrap.readinessService.state.score?.score
        let summary = PlanBootstrap.prescriptionService.state.summary
        await notificationScheduler.schedulePreWorkoutPrimeIfNeeded(
            summary: summary,
            readinessScore: readiness
        )
    }

    @MainActor
    static func refreshThresholdInsights() async {
        await thresholdInsightService.refresh(today: ReadinessBootstrap.readinessService.state.score)
    }
}
