import Core
import Foundation
import NutritionKit
import Persistence

struct MealLineItemSummary: Identifiable, Sendable, Equatable {
    let name: String
    let detail: String
    let energyKcal: Int

    var id: String { "\(name)-\(detail)-\(energyKcal)" }
}

struct LoggedMealDisplay: Identifiable, Sendable, Equatable {
    let meal: MealRecord
    let lineItems: [MealLineItemSummary]

    var id: UUID { meal.id }
}

@MainActor
@Observable
final class NutritionDayMealsStore {
    private(set) var mealsByBucket: [MealBucket: [LoggedMealDisplay]] = [:]

    init() {
        resetBuckets()
    }

    func reload(for helmDay: HelmDay) {
        let store = PersistenceBootstrap.persistenceStore
        let meals = (try? store.nutrition.fetchMeals(for: helmDay)) ?? []
        resetBuckets()

        for meal in meals {
            let lineItems = loadLineItems(for: meal, store: store)
            mealsByBucket[meal.bucket, default: []].append(
                LoggedMealDisplay(meal: meal, lineItems: lineItems)
            )
        }

        for bucket in MealBucket.allCases {
            mealsByBucket[bucket]?.sort { $0.meal.loggedAt < $1.meal.loggedAt }
        }
    }

    private func resetBuckets() {
        mealsByBucket = Dictionary(uniqueKeysWithValues: MealBucket.allCases.map { ($0, []) })
    }

    private func loadLineItems(for meal: MealRecord, store: PersistenceStore) -> [MealLineItemSummary] {
        if let records = try? store.foodLog.fetchLineItems(for: meal.id), !records.isEmpty {
            return records.map { item in
                MealLineItemSummary(
                    name: FoodLogDisplayFormatter.primaryTitle(
                        displayName: item.foodRef.displayName,
                        servingLabel: item.servingLabel
                    ),
                    detail: FoodLogDisplayFormatter.secondaryDetail(
                        displayName: item.foodRef.displayName,
                        servingLabel: item.servingLabel,
                        grams: item.grams
                    ),
                    energyKcal: Int(item.energyKcal.rounded())
                )
            }
        }

        let energyKcal = Int((meal.energy?.kilocalories ?? 0).rounded())
        guard energyKcal > 0 || !meal.name.isEmpty else { return [] }

        return [
            MealLineItemSummary(
                name: meal.name,
                detail: sourceLabel(for: meal.source),
                energyKcal: energyKcal
            )
        ]
    }

    private func sourceLabel(for source: MealRecord.Source) -> String {
        switch source {
        case .healthKit:
            "Imported"
        case .manual:
            "Manual"
        case .photo:
            "Photo"
        case .barcode:
            "Barcode"
        case .quickAdd:
            "Quick add"
        case .alcohol:
            "Alcohol"
        case .template:
            "Template"
        }
    }
}

#if DEBUG
extension NutritionDayMealsStore {
    static func previewStore() -> NutritionDayMealsStore {
        let store = NutritionDayMealsStore()
        let day = HelmDay(year: 2026, month: 7, day: 24)
        let breakfastID = UUID()
        store.mealsByBucket[.breakfast] = [
            LoggedMealDisplay(
                meal: MealRecord(
                    id: breakfastID,
                    helmDay: day,
                    name: "Oats and berries",
                    loggedAt: Date(),
                    bucket: .breakfast,
                    energy: Energy(kilocalories: 420),
                    proteinGrams: 18,
                    carbohydrateGrams: 62,
                    fatGrams: 9,
                    source: .manual
                ),
                lineItems: [
                    MealLineItemSummary(name: "Rolled oats", detail: "80 g", energyKcal: 300),
                    MealLineItemSummary(name: "Blueberries", detail: "100 g", energyKcal: 57)
                ]
            )
        ]
        return store
    }
}
#endif
