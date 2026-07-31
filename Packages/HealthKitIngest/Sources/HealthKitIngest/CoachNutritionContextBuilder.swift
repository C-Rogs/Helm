import Core
import Foundation
import Persistence
import PlanKit

/// Today's meal diary and macro targets for coach nutrition Q&A.
public enum CoachNutritionContextBuilder {
    public static func diaryBlock(
        from store: PersistenceStore,
        for helmDay: HelmDay,
        prescriptionSummary: PrescribedSessionSummary? = nil,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default,
        now: Date = Date()
    ) async -> String {
        let engine = NutritionEngine(persistence: store, calendar: calendar, cutoff: cutoff)
        let snapshot = await engine.snapshot(for: helmDay, prescriptionSummary: prescriptionSummary, now: now)
        let meals = (try? store.nutrition.fetchMeals(for: helmDay)) ?? []

        var lines: [String] = [
            "day=\(helmDay.formatted)",
            "targets_kcal=\(snapshot.targets.caloriesKcal) protein_g=\(snapshot.targets.proteinGrams) carbs_g=\(snapshot.targets.carbohydrateGrams) fat_g=\(snapshot.targets.fatGrams)",
            "day_type=\(snapshot.dayType.rawValue)",
            "logging_complete=\(snapshot.loggingComplete)"
        ]

        if let intake = snapshot.actual?.totalEnergy?.kilocalories {
            lines.append("logged_kcal=\(format(intake))")
        }
        if let protein = snapshot.actual?.totalProteinGrams {
            lines.append("logged_protein_g=\(format(protein))")
        }
        if let carbs = snapshot.actual?.totalCarbohydrateGrams {
            lines.append("logged_carbs_g=\(format(carbs))")
        }
        if let fat = snapshot.actual?.totalFatGrams {
            lines.append("logged_fat_g=\(format(fat))")
        }

        let buckets = Dictionary(grouping: meals, by: \.bucket)
        for bucket in MealBucket.allCases {
            guard let bucketMeals = buckets[bucket], !bucketMeals.isEmpty else { continue }
            let entries = bucketMeals.map { meal in
                let kcal = meal.energy.map { "\(Int($0.kilocalories.rounded()))kcal" } ?? "?"
                return "id=\(meal.id.uuidString.lowercased()) \(meal.name) \(kcal)"
            }
            lines.append("\(bucket.rawValue): \(entries.joined(separator: "; "))")
        }

        if meals.isEmpty {
            lines.append("meals=none")
        }

        return lines.joined(separator: "\n")
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
