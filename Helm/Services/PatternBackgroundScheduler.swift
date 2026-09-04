import BackgroundTasks
import Foundation
import HealthKitIngest
import Persistence

/// Nightly PatternKit discovery on external power. Charging + 7-day stale in `ProactiveBootstrap` is the fallback.
enum PatternBackgroundScheduler {
    static let taskIdentifier = "com.cameronro.helm.pattern-evaluate"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(processing)
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGProcessingTask) {
        schedule()
        nonisolated(unsafe) let processing = task
        let work = Task {
            let service = PatternEvaluationService(store: PersistenceBootstrap.persistenceStore)
            await service.refresh(isCharging: true, forceDiscovery: true)
            processing.setTaskCompleted(success: !Task.isCancelled)
        }
        processing.expirationHandler = {
            work.cancel()
            processing.setTaskCompleted(success: false)
        }
    }
}
