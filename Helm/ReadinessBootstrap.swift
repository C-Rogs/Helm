import Foundation
import HealthKitIngest
import Persistence

enum ReadinessBootstrap {
    private static let engine = ReadinessEngine(persistence: PersistenceBootstrap.persistenceStore)
    @MainActor private static var startupRefreshTask: Task<Void, Never>?

    @MainActor
    static let readinessService = ReadinessService(engine: engine)

    static var readinessEngine: ReadinessEngine { engine }

    @MainActor
    static func start() {
        guard startupRefreshTask == nil else { return }

        startupRefreshTask = Task(priority: .userInitiated) { @MainActor in
            // Convert legacy per-sample TRIMP history before any recompute reads it.
            try? await engine.migrateTRIMPEpochIfNeeded()

            // Persisted score first so ARC paints before 180-day recompute.
            await readinessService.hydrateFromCache()
            await readinessService.refresh()
        }

        Task(priority: .utility) { @MainActor in
            observeIngest()
        }
    }

    /// Dashboard launch joins the startup compute when present, preventing a second
    /// 30-day history rebuild after the bootstrap task has already completed.
    @MainActor
    static func refreshForDashboard() async {
        if let startupRefreshTask {
            await startupRefreshTask.value
        } else {
            await readinessService.refresh()
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
