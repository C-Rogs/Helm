import CoachLLM
import Core
import Foundation
import HealthKitIngest
import Persistence

enum NutritionBootstrap {
    static let engine = NutritionEngine(persistence: PersistenceBootstrap.persistenceStore)
    static let weeklyCheckInService = NutritionWeeklyCheckInService(
        persistence: PersistenceBootstrap.persistenceStore
    )

    @MainActor
    static let nutritionService = NutritionService(engine: engine)

    static let foodResolver = FoodResolver(persistence: PersistenceBootstrap.persistenceStore)

    static let manualMealService = ManualMealService(
        localStore: ManualMealLocalStore(store: PersistenceBootstrap.persistenceStore)
    )

    static let pendingFoodImportService = PendingFoodImportService(
        persistence: PersistenceBootstrap.persistenceStore,
        foodResolver: foodResolver,
        actionExecutor: HelmActionExecutor(
            manualMealService: manualMealService,
            persistence: PersistenceBootstrap.persistenceStore,
            mealRepeatService: MealRepeatService(
                store: PersistenceBootstrap.persistenceStore,
                manualMealService: manualMealService
            )
        ),
        onResolved: { count in
            await PendingImportNotificationScheduler.postResolved(count: count)
            await MainActor.run {
                refreshNutrition()
            }
        }
    )

    private static let networkReconnectNotifier = NetworkReconnectNotifier()

    @MainActor
    static let mealRepeatService = MealRepeatService(
        store: PersistenceBootstrap.persistenceStore,
        manualMealService: manualMealService
    )

    @MainActor
    private static var cachedPhotoMealService: PhotoMealService?
    @MainActor
    private static var cachedPhotoMealAvailable: Bool?

    /// Cheap availability check. Does not build estimator or load CoFID.
    @MainActor
    static var isPhotoMealAvailable: Bool {
        if let cachedPhotoMealAvailable {
            return cachedPhotoMealAvailable
        }
        let available = MealVisionRouter(apiKeyStore: APIKeyStore()).isAvailable
        cachedPhotoMealAvailable = available
        return available
    }

    @MainActor
    static var photoMealService: PhotoMealService? {
        if let cachedPhotoMealService {
            return cachedPhotoMealService
        }
        guard isPhotoMealAvailable else { return nil }
        let service = PhotoMealService(
            estimator: PhotoMacroEstimator(router: MealVisionRouter(apiKeyStore: APIKeyStore())),
            localStore: PhotoMealLocalStore(store: PersistenceBootstrap.persistenceStore),
            hkWrites: manualMealService.hkWrites
        )
        cachedPhotoMealService = service
        return service
    }

    /// Call when API keys change so photo meal availability is re-evaluated.
    @MainActor
    static func invalidatePhotoMealServiceCache() {
        cachedPhotoMealService = nil
        cachedPhotoMealAvailable = nil
    }

    @MainActor
    static let usualMealScheduler = UsualMealNotificationScheduler(
        persistence: PersistenceBootstrap.persistenceStore
    )

    @MainActor
    static func start() {
        networkReconnectNotifier.setHandler {
            Task(priority: .utility) {
                _ = await pendingFoodImportService.resolvePendingImports()
                await MainActor.run {
                    refreshNutrition()
                }
            }
        }

        Task(priority: .userInitiated) {
            let summary = PlanBootstrap.prescriptionService.state.summary
            await nutritionService.refresh(prescriptionSummary: summary)
        }

        Task(priority: .utility) {
            observeIngest()
        }

        Task(priority: .utility) {
            _ = await pendingFoodImportService.resolvePendingImports()
            refreshNutrition()
        }
    }

    @MainActor
    static var lastViewedHelmDay: HelmDay?

    @MainActor
    static func refreshNutrition(for helmDay: HelmDay? = nil) {
        Task {
            let summary = PlanBootstrap.prescriptionService.state.summary
            let day = helmDay ?? lastViewedHelmDay ?? HelmDay.day(for: Date(), calendar: .current)
            await nutritionService.refresh(for: day, prescriptionSummary: summary)
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
                    refreshNutrition()
                }
            }
        }
    }
}
