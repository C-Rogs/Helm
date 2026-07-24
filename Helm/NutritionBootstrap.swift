import CoachLLM
import Foundation
import HealthKitIngest
import Persistence

enum NutritionBootstrap {
    static let engine = NutritionEngine(persistence: PersistenceBootstrap.persistenceStore)

    @MainActor
    static let nutritionService = NutritionService(engine: engine)

    @MainActor
    static var photoMealService: PhotoMealService? {
        let keyStore = APIKeyStore()
        let router = MealVisionRouter(apiKeyStore: keyStore)
        guard router.isAvailable else { return nil }
        return PhotoMealService(
            estimator: PhotoMacroEstimator(router: router),
            localStore: PhotoMealLocalStore(store: PersistenceBootstrap.persistenceStore)
        )
    }

    @MainActor
    static func start() {
        Task(priority: .userInitiated) {
            let summary = PlanBootstrap.prescriptionService.state.summary
            await nutritionService.refresh(prescriptionSummary: summary)
        }

        Task(priority: .utility) {
            observeIngest()
        }
    }

    @MainActor
    static func refreshNutrition() {
        Task {
            let summary = PlanBootstrap.prescriptionService.state.summary
            await nutritionService.refresh(prescriptionSummary: summary)
        }
    }

    @MainActor
    private static func observeIngest() {
        let ingest = HealthKitBootstrap.healthKitIngest
        for family in [HealthKitMetricFamily.nutrition, .bodyComposition] {
            Task {
                for await snapshot in ingest.updates(for: family) {
                    guard snapshot.status.lastSyncSampleCount > 0
                        || snapshot.status.lastSyncDeletedCount > 0
                    else { continue }
                    await nutritionService.recomputeAfterIngest(affectedFamilies: [family])
                    await refreshNutrition()
                }
            }
        }
    }
}
