import Core
import DesignSystem
import SwiftUI

struct NutritionMealBucketSection: View {
    let bucket: MealBucket
    let meals: [LoggedMealDisplay]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bucket.displayName)
                        .helmType(.label)
                    Spacer()
                    if bucketTotalKcal > 0 {
                        Text("\(bucketTotalKcal) kcal")
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                }

                if meals.isEmpty {
                    bucketEmptyState
                } else {
                    ForEach(meals) { meal in
                        mealBlock(meal)
                    }
                }
            }
        }
    }

    private var bucketEmptyState: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text("Nothing logged")
                .helmType(.body, color: HelmColor.fgSecondary)
            Text("Tap + to add \(bucket.displayName.lowercased()).")
                .helmType(.body, color: HelmColor.fgMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, HelmSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func mealBlock(_ display: LoggedMealDisplay) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            if meals.count > 1 || display.lineItems.count > 1 {
                Text(display.meal.name)
                    .helmType(.body, color: HelmColor.fgSecondary)
            }

            ForEach(display.lineItems) { item in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                        Text(item.name)
                            .helmType(.body)
                        Text(item.detail)
                            .helmType(.monoTag, color: HelmColor.fgMuted)
                    }
                    Spacer()
                    Text("\(item.energyKcal) kcal")
                        .helmType(.number, color: HelmColor.fgSecondary)
                }
            }
        }
        .padding(.vertical, HelmSpacing.xxs)
    }

    private var bucketTotalKcal: Int {
        meals.reduce(0) { partial, meal in
            partial + meal.lineItems.reduce(0) { $0 + $1.energyKcal }
        }
    }
}

#Preview("Breakfast filled") {
    NutritionMealBucketSection(
        bucket: .breakfast,
        meals: NutritionDayMealsStore.previewStore().mealsByBucket[.breakfast] ?? []
    )
    .padding()
    .helmTheme()
}

#Preview("Lunch empty") {
    NutritionMealBucketSection(bucket: .lunch, meals: [])
        .padding()
        .helmTheme()
}

#Preview("Dinner filled") {
    let day = HelmDay(year: 2026, month: 7, day: 24)
    NutritionMealBucketSection(
        bucket: .dinner,
        meals: [
            LoggedMealDisplay(
                meal: MealRecord(
                    helmDay: day,
                    name: "Salmon bowl",
                    loggedAt: Date(),
                    bucket: .dinner,
                    energy: Energy(kilocalories: 640),
                    proteinGrams: 42,
                    carbohydrateGrams: 48,
                    fatGrams: 22,
                    source: .photo
                ),
                lineItems: [
                    MealLineItemSummary(name: "Salmon bowl", detail: "Photo", energyKcal: 640)
                ]
            )
        ]
    )
    .padding()
    .helmTheme()
}

#Preview("Snacks empty data sheet") {
    NutritionMealBucketSection(bucket: .snacks, meals: [])
        .padding()
        .helmTheme()
        .environment(\.helmSkin, .dataSheet)
}
