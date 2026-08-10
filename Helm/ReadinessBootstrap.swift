import Foundation
import HealthKitIngest
import Persistence

enum ReadinessBootstrap {
    private static let engine = ReadinessEngine(persistence: PersistenceBootstrap.persistenceStore)

    @MainActor
    static let readinessService = ReadinessService(engine: engine)

    static var readinessEngine: ReadinessEngine { engine }

    @MainActor
    static func start() {
        Task(priority: .userInitiated) { @MainActor in
            // Persisted score first so ARC paints before 180-day recompute.
            await readinessService.hydrateFromCache()
            await readinessService.refresh()
        }

        Task(priority: .utility) { @MainActor in
            observeIngest()
        }
    }

    @MainActor
    private static func observeIngest() {
        let ingest = HealthKitBootstrap.healthKitIngest
        for family in [HealthKitMetricFamily.vitals, .sleep, .workouts] {
            Task { @MainActor in
                for await snapshot in ingest.updates(for: family) {
                    guard snapshot.status.lastSyncSampleCount > 0
                        || snapshot.status.lastSyncDeletedCount > 0
                    else { continue }
                    await readinessService.recomputeAfterIngest(
                        affectedFamilies: [family]
                    )
                    await WatchReadinessBootstrap.pushCurrentReadiness()
                }
            }
        }
    }
}
