import Core
import Foundation
import NutritionKit
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
            "calorie_authority=weekly_budget",
            "eat_to_kcal=\(snapshot.eatToKcal)",
            "planned_kcal=\(snapshot.plannedKcal)",
            "targets_kcal=\(snapshot.targets.caloriesKcal) protein_g=\(snapshot.targets.proteinGrams) carbs_g=\(snapshot.targets.carbohydrateGrams) fat_g=\(snapshot.targets.fatGrams)",
            "day_type=\(snapshot.dayType.rawValue)",
            "logging_complete=\(snapshot.loggingComplete)"
        ]
        if let demand = snapshot.budgetDay?.demand {
            lines.append("demand=\(demand.rawValue)")
        }
        if let budget = snapshot.weeklyBudget {
            lines.append("weekly_tgt_kcal=\(budget.targetCaloriesKcal)")
            lines.append("weekly_remaining_kcal=\(budget.remainingCaloriesKcal)")
        }

        if let tdee = snapshot.trend.estimatedTDEEKcal {
            lines.append("estimated_tdee=\(format(tdee))kcal")
        }
        if let trendWeight = snapshot.trend.smoothedTrendWeightKg {
            lines.append("trend_weight=\(format(trendWeight))kg")
        }
        if let priorWeight = snapshot.trend.priorWeekTrendWeightKg {
            lines.append("prior_week_trend_weight=\(format(priorWeight))kg")
        }
        if let intakeAvg = snapshot.trend.weeklyIntakeAverageKcal {
            lines.append("weekly_intake_avg=\(format(intakeAvg))kcal")
        }
        if let lastUpdate = snapshot.trend.lastWeeklyUpdate {
            lines.append("last_weekly_update=\(lastUpdate.formatted)")
        }

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

        if let burnKcal = snapshot.activeEnergyFreshness.displayKilocalories {
            lines.append("active_energy_kcal=\(burnKcal)")
            lines.append("active_energy_freshness=\(snapshot.activeEnergyFreshness.freshnessLabel)")
        } else {
            lines.append("active_energy_freshness=\(snapshot.activeEnergyFreshness.freshnessLabel)")
        }
        if let note = snapshot.activeEnergyFreshness.note {
            lines.append("active_energy_note=\(note)")
        }
        if case let .fresh(burned) = snapshot.activeEnergyFreshness, burned > 0 {
            lines.append("adjusted_target_kcal=\(snapshot.energyBalance.adjustedTargetKcal.map { String($0) } ?? "?")")
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

    /// Weekly nutrition budget block for coach context. Provides the engine's
    /// exact Monday-Sunday plan, consumed/remaining totals, per-day allocations
    /// and demand reasons. Coach must quote these numbers, not recalculate.
    public static func weeklyBudgetBlock(
        from store: PersistenceStore,
        for helmDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) async -> String? {
        let engine = NutritionEngine(persistence: store, calendar: calendar, cutoff: cutoff)
        guard let budget = try? await engine.weeklyBudget(for: helmDay, prescriptionSummary: nil) else { return nil }

        var lines: [String] = [
            "week_start=\(budget.weekStart.formatted)",
            "weekly_tgt_kcal=\(budget.targetCaloriesKcal)",
            "consumed_kcal=\(budget.consumedCaloriesKcal)",
            "remaining_kcal=\(budget.remainingCaloriesKcal)"
        ]
        if budget.excessCaloriesKcal > 0 {
            lines.append("excess_kcal=\(budget.excessCaloriesKcal)")
        }

        for day in budget.days {
            let stateTag = day.isProvisional ? " [provisional]" : ""
            let reasonTag = day.reason == .consumed ? "" : " (\(day.reason.rawValue))"
            lines.append(
                "\(day.day.formatted) | \(day.demand.rawValue) | eat_to=\(day.eatToCaloriesKcal)kcal planned=\(day.plannedCaloriesKcal)kcal | P\(day.proteinGrams)g C\(day.carbohydrateGrams)g F\(day.fatGrams)g\(stateTag)\(reasonTag)"
            )
        }

        return lines.joined(separator: "\n")
    }
}
