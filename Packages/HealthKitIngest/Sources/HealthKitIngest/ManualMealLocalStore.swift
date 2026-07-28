import Core
import Foundation
import Persistence

/// Persists confirmed manual meals locally. Helm filters its own HealthKit writes from ingest,
/// so manual meals must land in GRDB explicitly for Dashboard and Trends to update.
public struct ManualMealLocalStore: Sendable {
    private let nutrition: NutritionRepository
    private let foodLog: FoodLogRepository
    private let nutritionLogStatus: NutritionLogStatusRepository
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
        nutritionLogStatus = store.nutritionLogStatus
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
            let normalizedItems = lineItems.map { item in
                MealLineItemRecord(
                    id: item.id,
                    mealID: mealID,
                    foodRef: item.foodRef,
                    grams: item.grams,
                    servingLabel: item.servingLabel,
                    energyKcal: item.energyKcal,
                    proteinG: item.proteinG,
                    carbsG: item.carbsG,
                    fatG: item.fatG,
                    sortOrder: item.sortOrder
                )
            }
            try foodLog.replaceLineItems(for: mealID, with: normalizedItems)
            for item in normalizedItems {
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

        try recomputeNutritionDay(helmDay: helmDay)
        try nutritionLogStatus.clearComplete(helmDay: helmDay)
        _ = now
    }

    public func fetchMeal(id: UUID) throws -> MealRecord? {
        try nutrition.fetchMeal(id: id)
    }

    public func updateSavedMeal(
        mealID: UUID,
        previousHelmDay: HelmDay,
        request: MealWriteRequest,
        saved: SavedMealSamples,
        bucket: MealBucket,
        source: MealRecord.Source,
        lineItems: [MealLineItemRecord]
    ) throws {
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
        if lineItems.isEmpty {
            try foodLog.deleteLineItems(for: mealID)
        } else {
            try foodLog.replaceLineItems(for: mealID, with: lineItems)
        }

        try recomputeNutritionDay(helmDay: helmDay)
        if helmDay != previousHelmDay {
            try recomputeNutritionDay(helmDay: previousHelmDay)
            try nutritionLogStatus.clearComplete(helmDay: previousHelmDay)
        }
        try nutritionLogStatus.clearComplete(helmDay: helmDay)
    }

    @discardableResult
    public func deleteMeal(id: UUID) throws -> MealRecord? {
        guard let meal = try nutrition.fetchMeal(id: id) else { return nil }
        let helmDay = meal.helmDay
        try nutrition.deleteMeal(id: id)

        let remaining = try nutrition.fetchMeals(for: helmDay)
        if remaining.isEmpty {
            try nutrition.deleteDay(helmDay: helmDay)
        } else {
            try recomputeNutritionDay(helmDay: helmDay)
        }
        return meal
    }

    private func recomputeNutritionDay(helmDay: HelmDay) throws {
        let dayMeals = try nutrition.fetchMeals(for: helmDay)
        let nutritionDay = HealthKitDayAggregator.nutritionDay(from: dayMeals, helmDay: helmDay)
        try nutrition.upsertDay(nutritionDay)
    }
}
