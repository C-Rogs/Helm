import Core
import DesignSystem
import HealthKitIngest
import Observation

@MainActor
@Observable
final class MealEditController {
    var selectedMeal: LoggedMealDisplay?
    var isSaving = false
    var showsDeleteConfirm = false
    var errorMessage: String?

    private let actionExecutor: HelmActionExecutor
    private let onChanged: @MainActor () -> Void

    init(
        actionExecutor: HelmActionExecutor,
        onChanged: @escaping @MainActor () -> Void = {}
    ) {
        self.actionExecutor = actionExecutor
        self.onChanged = onChanged
    }

    static func isEditable(_ meal: MealRecord) -> Bool {
        meal.source != .healthKit
    }

    func beginEdit(_ display: LoggedMealDisplay) {
        guard Self.isEditable(display.meal) else { return }
        selectedMeal = display
    }

    func cancel() {
        selectedMeal = nil
        errorMessage = nil
    }

    func save(
        name: String,
        lineItems: [MealLineItemEditor.EditableLineItem],
        quickAddMacros: FoodPortionMacros?,
        bucket: MealBucket
    ) async {
        guard let display = selectedMeal else { return }
        let meal = display.meal
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a meal name."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let records: [MealLineItemRecord]
            let macros: FoodPortionMacros

            if lineItems.isEmpty, let quickAddMacros {
                macros = quickAddMacros
                records = []
            } else {
                records = lineItems.enumerated().map { index, entry in
                    MealLineItemTemplateMapping.record(
                        from: entry.item,
                        mealID: meal.id,
                        sortOrder: index,
                        servingLabel: entry.servingLabel
                    )
                }
                macros = FoodPortionMacros(
                    energyKcal: records.reduce(0) { $0 + $1.energyKcal },
                    proteinG: records.reduce(0) { $0 + $1.proteinG },
                    carbsG: records.reduce(0) { $0 + $1.carbsG },
                    fatG: records.reduce(0) { $0 + $1.fatG }
                )
            }

            _ = try await actionExecutor.run(
                .meal(.updateMeal(
                    mealID: meal.id,
                    name: trimmedName,
                    bucket: bucket,
                    loggedAt: meal.loggedAt,
                    macros: macros,
                    lineItems: records,
                    source: meal.source,
                    helmDay: meal.helmDay
                ))
            )
            selectedMeal = nil
            HapticEngine.shared.play(.mealConfirmed)
            onChanged()
        } catch {
            errorMessage = "Could not save changes. Try again."
        }
    }

    func delete() async {
        guard let meal = selectedMeal?.meal else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await actionExecutor.run(
                .meal(.deleteMeal(mealID: meal.id, helmDay: meal.helmDay))
            )
            selectedMeal = nil
            HapticEngine.shared.play(.mealConfirmed)
            onChanged()
        } catch {
            errorMessage = "Could not delete entry. Try again."
        }
    }

    func dismissError() {
        errorMessage = nil
    }
}
