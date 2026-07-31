import Core
import DesignSystem
import NutritionKit
import SwiftUI

struct NutritionMealBucketSection: View {
    let bucket: MealBucket
    let meals: [LoggedMealDisplay]
    var isPhotoAvailable = false
    var onCopyToToday: (() -> Void)?
    var onSaveTemplate: (() -> Void)?
    var onMealTap: ((LoggedMealDisplay) -> Void)?
    var onAddFood: ((BucketFoodLogAction) -> Void)?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bucket.displayName)
                        .helmType(.label)
                    Spacer()
                    if bucketTotalKcal > 0 || bucketMacroCompactText != nil {
                        VStack(alignment: .trailing, spacing: HelmSpacing.xxs) {
                            if bucketTotalKcal > 0 {
                                Text("\(bucketTotalKcal) kcal")
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                            }
                            if let bucketMacroCompactText {
                                Text(bucketMacroCompactText)
                                    .helmType(.monoTag, color: HelmColor.fgMuted)
                            }
                        }
                    }
                    if onCopyToToday != nil || onSaveTemplate != nil {
                        Menu {
                            if let onCopyToToday {
                                Button("Copy yesterday to today", action: onCopyToToday)
                            }
                            if let onSaveTemplate {
                                Button("Save as template", action: onSaveTemplate)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(HelmColor.fgMuted)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.helmPressable)
                        .accessibilityLabel("\(bucket.displayName) actions")
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
            .padding(.bottom, onAddFood == nil ? 0 : HelmSpacing.xl)
        }
        .overlay(alignment: .bottomTrailing) {
            if let onAddFood {
                BucketFoodLogMenu(
                    bucket: bucket,
                    isPhotoAvailable: isPhotoAvailable,
                    onAction: onAddFood
                )
                .padding(HelmSpacing.sm)
            }
        }
    }

    private var bucketEmptyState: some View {
        Text("Nothing logged")
            .helmType(.body, color: HelmColor.fgSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, HelmSpacing.xs)
    }

    @ViewBuilder
    private func mealBlock(_ display: LoggedMealDisplay) -> some View {
        let content = VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            if shouldShowMealHeader(for: display) {
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

        if let onMealTap, MealEditController.isEditable(display.meal) {
            Button {
                onMealTap(display)
            } label: {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.helmPressable)
            .accessibilityLabel("Edit \(display.meal.name)")
        } else {
            content
        }
    }

    private var bucketTotalKcal: Int {
        meals.reduce(0) { partial, meal in
            partial + meal.lineItems.reduce(0) { $0 + $1.energyKcal }
        }
    }

    private var bucketMacroCompactText: String? {
        var protein = 0
        var carbs = 0
        var fat = 0
        for meal in meals {
            protein += Int((meal.meal.proteinGrams ?? 0).rounded())
            carbs += Int((meal.meal.carbohydrateGrams ?? 0).rounded())
            fat += Int((meal.meal.fatGrams ?? 0).rounded())
        }
        return MacroCompactFormatter.compact(
            proteinGrams: protein,
            carbohydrateGrams: carbs,
            fatGrams: fat
        )
    }

    private func shouldShowMealHeader(for display: LoggedMealDisplay) -> Bool {
        display.lineItems.count > 1
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
