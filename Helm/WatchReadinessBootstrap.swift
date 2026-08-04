import Core
import Diagnostics
import Foundation
import HealthKitIngest
import ReadinessKit

enum WatchReadinessBootstrap {
    @MainActor
    static let coordinator = WatchSessionCoordinator(role: .phone)

    @MainActor
    static func start() {
        coordinator.onDiagnosticEvent = { event, detail in
            Task {
                var context: [String: String] = ["source": "watchRelay"]
                if let detail, !detail.isEmpty {
                    context["detail"] = String(detail.prefix(200))
                }
                await DiagnosticsLog.shared.record(
                    category: .watch,
                    level: .info,
                    message: event.rawValue,
                    context: context
                )
            }
        }
        MirroredWorkoutSessionBridge.shared.start()
        Task(priority: .utility) {
            observeReadiness()
        }
    }

    @MainActor
    private static func observeReadiness() {
        Task {
            await pushCurrentReadiness(force: true)
        }

        Task {
            let ingest = HealthKitBootstrap.healthKitIngest
            for await snapshot in ingest.updates(for: .workouts) {
                guard snapshot.status.lastSyncSampleCount > 0 else { continue }
                await pushCurrentReadiness()
            }
        }

        Task {
            let ingest = HealthKitBootstrap.healthKitIngest
            for await snapshot in ingest.updates(for: .vitals) {
                guard snapshot.status.lastSyncSampleCount > 0 else { continue }
                await ReadinessBootstrap.readinessService.refresh()
                await pushCurrentReadiness()
            }
        }
    }

    @MainActor
    static func pushCurrentReadiness(force: Bool = false) async {
        await ReadinessBootstrap.readinessService.refresh()

        guard case let .scored(score) = ReadinessBootstrap.readinessService.state else {
            return
        }

        let briefSummary = BriefBootstrap.briefService.briefSummaryForWatch
        let day = HelmDay.day(for: .now, calendar: .current)

        coordinator.pushReadiness(
            score: score.score,
            band: score.band.rawValue,
            helmDay: day,
            briefSummary: briefSummary,
            force: force
        )
    }
}
