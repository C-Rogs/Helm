import Core
import Foundation
import Persistence

/// Persists confirmed photo meals locally. Helm filters its own HealthKit writes from ingest,
/// so photo meals must land in GRDB explicitly for Dashboard and Trends to update.
public struct PhotoMealLocalStore: Sendable {
    private let nutrition: NutritionRepository
    private let nutritionLogStatus: NutritionLogStatusRepository
    private let calendar: Calendar
    private let cutoff: DayCutoff

    public init(
        store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        nutrition = store.nutrition
        nutritionLogStatus = store.nutritionLogStatus
        self.calendar = calendar
        self.cutoff = cutoff
    }

    public func recordSavedMeal(
        _ request: MealWriteRequest,
        saved: SavedMealSamples,
        bucket: MealBucket = .snacks
    ) throws {
        let mealID = UUID(uuidString: request.mealID) ?? saved.energy.id
        let helmDay = HelmDay.day(for: request.loggedAt, cutoff: cutoff, calendar: calendar)
        let meal = MealRecord(
            id: mealID,
            helmDay: helmDay,
            name: request.name,
            loggedAt: request.loggedAt,
            bucket: bucket,
            energy: Energy(kilocalories: request.caloriesKcal),
            proteinGrams: request.proteinG,
            carbohydrateGrams: request.carbsG,
            fatGrams: request.fatG,
            source: .photo,
            externalSampleID: saved.energy.id.uuidString
        )

        try nutrition.upsertMeal(meal)
        if !request.lineItems.isEmpty {
            try PhotoMealLineItemArchive.save(lineItems: request.lineItems, mealID: mealID)
        }
        let dayMeals = try nutrition.fetchMeals(for: helmDay)
        let nutritionDay = HealthKitDayAggregator.nutritionDay(from: dayMeals, helmDay: helmDay)
        try nutrition.upsertDay(nutritionDay)
        try nutritionLogStatus.clearComplete(helmDay: helmDay)
    }
}
