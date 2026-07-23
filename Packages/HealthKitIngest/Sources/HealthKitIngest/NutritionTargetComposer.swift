import Core
import Foundation

/// Interim phase-based macro targets until NutritionKit lands at M9.1.
public enum NutritionTargetComposer {
    private static let defaultBodyMassKg = 75.0
    private static let proteinPerKg = 2.0
    private static let maintenanceKcalPerKg = 33.0

    public static func compose(
        phase: TrainingPhase,
        bodyMassKg: Double?,
        isTrainingDay: Bool
    ) -> NutritionTargetsSummary {
        let mass = bodyMassKg ?? defaultBodyMassKg
        let proteinGrams = Int((mass * proteinPerKg).rounded())
        let proteinKcal = proteinGrams * 4

        var calories = Int((mass * maintenanceKcalPerKg).rounded())
        switch phase {
        case .cut:
            calories -= 500
        case .gain:
            calories += 300
        case .maintain:
            break
        }

        let remainingKcal = max(calories - proteinKcal, 0)
        let carbShare = isTrainingDay ? 0.45 : 0.35
        let carbKcal = Int((Double(remainingKcal) * carbShare).rounded())
        let fatKcal = max(remainingKcal - carbKcal, 0)
        let carbohydrateGrams = carbKcal / 4
        let fatGrams = fatKcal / 9

        return NutritionTargetsSummary(
            caloriesKcal: calories,
            proteinGrams: proteinGrams,
            carbohydrateGrams: carbohydrateGrams,
            fatGrams: fatGrams,
            dayType: isTrainingDay ? "training" : "rest"
        )
    }
}
