import Core
import Foundation
import Persistence

/// Groups persisted meals by bucket for a diary day.
/// Mirrors the meal fetch + bucket grouping `NutritionDayMealsStore.reload` performs before display enrichment.
public enum NutritionMealBucketProjection {
    public static func mealsByBucket(
        for helmDay: HelmDay,
        store: PersistenceStore
    ) throws -> [MealBucket: [MealRecord]] {
        let meals = try store.nutrition.fetchMeals(for: helmDay)
        var grouped = Dictionary(uniqueKeysWithValues: MealBucket.allCases.map { ($0, [MealRecord]()) })
        for meal in meals {
            grouped[meal.bucket, default: []].append(meal)
        }
        for bucket in MealBucket.allCases {
            grouped[bucket]?.sort { $0.loggedAt < $1.loggedAt }
        }
        return grouped
    }
}
