import Core
import Foundation
import HealthKitIngest
import Persistence
import SwiftUI

enum TrainBootstrap {
    private static let persistence = PersistenceBootstrap.persistenceStore
    private static let engine = ActiveSessionEngine(repository: persistence.activeSessions)

    @MainActor
    static let sideEffects = WorkoutSessionSideEffects(persistence: persistence)

    @MainActor
    static let sessionController = TrainSessionController(
        store: ActiveSessionStore(engine: engine),
        persistence: persistence,
        sideEffects: sideEffects,
        prescriptionService: PlanBootstrap.prescriptionService
    )

    @MainActor
    static let historyController = WorkoutHistoryController(persistence: persistence)

    @MainActor
    static let importController = WorkoutImportController(persistence: persistence)

    @MainActor
    static func start() {
        Task {
            historyController.refresh()
            await sessionController.recoverOnLaunch()
            await RestNotificationRouter.processPendingLaunchNotificationIfNeeded()
        }
    }
}
