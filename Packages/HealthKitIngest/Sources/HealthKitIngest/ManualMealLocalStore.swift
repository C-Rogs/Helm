import Core
import Foundation
import Persistence

/// Persists confirmed manual meals locally. Helm filters its own HealthKit writes from ingest,
/// so manual meals must land in GRDB explicitly for Dashboard and Trends to update.
public struct ManualMealLocalStore: Sendable {
    private let nutrition: NutritionRepository
    private let foodLog: FoodLogRepository
    private let calendar: Calendar
    private let cutoff: DayCutoff
    private let now: @Sendable () -> Date

    public init(
        store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        nutrition = store.nutrition
        foodLog = store.foodLog
        self.calendar = calendar
        self.cutoff = cutoff
        self.now = now
    }

    public func recordSavedMeal(
        request: MealWriteRequest,
        saved: SavedMealSamples,
        bucket: MealBucket,
        source: MealRecord.Source,
        lineItems: [MealLineItemRecord] = []
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
            source: source,
            externalSampleID: saved.energy.id.uuidString
        )

        try nutrition.upsertMeal(meal)
        if !lineItems.isEmpty {
            try foodLog.replaceLineItems(for: mealID, with: lineItems)
            for item in lineItems {
                try foodLog.upsertRecent(
                    FoodLogRecent(
                        ref: item.foodRef,
                        grams: item.grams,
                        servingLabel: item.servingLabel,
                        lastUsedAt: request.loggedAt
                    )
                )
                try foodLog.upsertPortionPreference(
                    FoodPortionPreference(
                        foodRef: item.foodRef,
                        grams: item.grams,
                        servingLabel: item.servingLabel,
                        lastUsedAt: request.loggedAt
                    )
                )
            }
        }

        let dayMeals = try nutrition.fetchMeals(for: helmDay)
        let nutritionDay = HealthKitDayAggregator.nutritionDay(from: dayMeals, helmDay: helmDay)
        try nutrition.upsertDay(nutritionDay)
        _ = now
    }
}
