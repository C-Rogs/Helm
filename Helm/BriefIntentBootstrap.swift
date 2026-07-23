import Core
import Foundation
import HealthKitIngest
import Persistence

enum BriefIntentBootstrap {
    private static let missStore = BriefIntentMissStore(
        metadata: PersistenceBootstrap.persistenceStore.appMetadata
    )

    private static let briefEngine = BriefEngine(
        persistence: PersistenceBootstrap.persistenceStore,
        prescriptionEngine: PlanBootstrap.engine
    )

    static let runner = BriefIntentRunner(
        ingest: HealthKitBootstrap.healthKitIngest,
        readinessEngine: ReadinessBootstrap.readinessEngine,
        prescriptionEngine: PlanBootstrap.engine,
        briefEngine: briefEngine,
        missStore: missStore,
        protectedData: LiveProtectedDataChecker(),
        notificationPoster: LiveBriefNotificationPoster()
    )

    static func hasPendingMiss(for day: HelmDay) -> Bool {
        (try? missStore.hasPendingMiss(for: day)) ?? false
    }
}
