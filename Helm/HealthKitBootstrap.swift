import Foundation
import HealthKitIngest
import Persistence

enum HealthKitBootstrap {
    private static let anchorDirectory: URL = {
        do {
            return try DatabaseLocation.defaultDatabaseURL().deletingLastPathComponent()
        } catch {
            fatalError("Failed to resolve HealthKit anchor directory: \(error)")
        }
    }()

    private static let ingest: HealthKitIngest = {
        HealthKitIngest(
            persistence: PersistenceBootstrap.persistenceStore,
            anchorDirectoryURL: anchorDirectory
        )
    }()

    private static let backfill: BackfillService = {
        BackfillService(
            persistence: PersistenceBootstrap.persistenceStore,
            anchorDirectoryURL: anchorDirectory,
            readinessEngine: ReadinessBootstrap.readinessEngine
        )
    }()

    static var healthKitIngest: HealthKitIngest { ingest }
    static var backfillService: BackfillService { backfill }

    /// Toggles HealthKit observer queries on or off.
    /// Festival mode calls this to stop/start background delivery wakes.
    static func setHealthKitObserving(_ enabled: Bool) async {
        if enabled {
            await ingest.startObserving()
        } else {
            await ingest.stopObserving()
        }
    }

    static func start() {
        Task(priority: .utility) {
            await bootstrapIfNeeded()
        }
    }

    /// Runs deferred bootstrap work after onboarding completes.
    static func startAfterOnboarding() {
        Task(priority: .utility) {
            await bootstrapIfNeeded()
            guard UserDefaults.standard.bool(forKey: OnboardingStore.completedDefaultsKey) else { return }
            scheduleDefaultBackfill()
        }
    }

    private static func shouldDeferBackfill() -> Bool {
        !UserDefaults.standard.bool(forKey: OnboardingStore.completedDefaultsKey)
    }

    private static func bootstrapIfNeeded() async {
        let window = BackfillWindow.sixMonths()
        let backfillComplete = await backfill.isComplete(for: window)
        let shouldStart = await ingest.shouldBootstrapOnLaunch(backfillComplete: backfillComplete)
        guard shouldStart else { return }

        try? await HealthKitV19AnchorMigration.runIfNeeded { kind in
            try await ingest.resetAnchor(for: kind)
        }

        try? await ingest.requestAuthorization()
        await ingest.startObserving()
        let outcome = await ingest.syncNow()
        await ReadinessBootstrap.readinessService.recomputeAfterIngest(
            affectedFamilies: outcome.affectedFamilies
        )
        if !shouldDeferBackfill() {
            scheduleDefaultBackfill()
        }
    }

    static func scheduleDefaultBackfill() {
        Task(priority: .utility) {
            for await _ in await backfill.runDefaultIfNeeded() {}
            await ReadinessBootstrap.readinessService.refresh()
        }
    }

    static func scheduleBackfillAfterAnchorReset() {
        Task(priority: .utility) {
            let window = BackfillWindow.sixMonths()
            try? await backfill.resetCursor(for: window)
            for await _ in await backfill.run(window: window) {}
            await ReadinessBootstrap.readinessService.refresh()
        }
    }
}
