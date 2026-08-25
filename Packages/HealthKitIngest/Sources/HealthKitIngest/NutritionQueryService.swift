import CoachLLM
import Core
import Foundation
import Persistence

/// On-demand nutrition engine lookups for coach nutrition_query.v1.
/// Exposes exact engine numbers (TDEE, trend weight, weekly budget, intake history,
/// targets) without bloating the 14-day context window.
public struct NutritionQueryService: Sendable {
    private let store: PersistenceStore
    private let calendar: Calendar
    private let cutoff: DayCutoff

    public init(
        store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.store = store
        self.calendar = calendar
        self.cutoff = cutoff
    }

    public func run(_ payload: NutritionQueryPayload, now: Date = Date()) async throws -> String {
        let today = HelmDay.day(for: now, calendar: calendar)
        switch payload.queryType {
        case .today:
            return await todayBlock(today: today)
        case .day:
            let day = parseDay(payload.helmDay) ?? today
            return await dayBlock(day)
        case .range:
            let lookback = min(max(payload.lookbackDays ?? 7, 1), 30)
            return try await rangeBlock(endingAt: today, lookbackDays: lookback)
        case .weeklyBudget:
            return await weeklyBudgetBlock(asOf: today)
        }
    }

    // MARK: - Today

    private func todayBlock(today: HelmDay) async -> String {
        let engine = NutritionEngine(persistence: store, calendar: calendar, cutoff: cutoff)
        let snapshot = await engine.snapshot(for: today, prescriptionSummary: nil, now: Date())
        var lines: [String] = [
            "query=today day=\(today.formatted)",
            "targets_kcal=\(snapshot.targets.caloriesKcal) protein_g=\(snapshot.targets.proteinGrams) carbs_g=\(snapshot.targets.carbohydrateGrams) fat_g=\(snapshot.targets.fatGrams)",
            "logging_complete=\(snapshot.loggingComplete)"
        ]
        if let tdee = snapshot.trend.estimatedTDEEKcal {
            lines.append("estimated_tdee=\(format(tdee))kcal")
        }
        if let trendWeight = snapshot.trend.smoothedTrendWeightKg {
            lines.append("trend_weight=\(format(trendWeight))kg")
        }
        if let intake = snapshot.actual?.totalEnergy?.kilocalories {
            lines.append("logged_kcal=\(format(intake))")
        }
        if let protein = snapshot.actual?.totalProteinGrams {
            lines.append("logged_protein_g=\(format(protein))")
        }
        if let intakeAvg = snapshot.trend.weeklyIntakeAverageKcal {
            lines.append("weekly_intake_avg=\(format(intakeAvg))kcal")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Day

    private func dayBlock(_ day: HelmDay) async -> String {
        let engine = NutritionEngine(persistence: store, calendar: calendar, cutoff: cutoff)
        let snapshot = await engine.snapshot(for: day, prescriptionSummary: nil, now: Date())
        let meals = (try? store.nutrition.fetchMeals(for: day)) ?? []
        let isPast = day < HelmDay.day(for: Date(), calendar: calendar)

        var lines: [String] = [
            "query=day day=\(day.formatted)\(isPast ? " [past]" : " [future]")",
            "targets_kcal=\(snapshot.targets.caloriesKcal) protein_g=\(snapshot.targets.proteinGrams) carbs_g=\(snapshot.targets.carbohydrateGrams) fat_g=\(snapshot.targets.fatGrams)"
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
        if !meals.isEmpty {
            let buckets = Dictionary(grouping: meals, by: \.bucket)
            for bucket in MealBucket.allCases {
                guard let bucketMeals = buckets[bucket], !bucketMeals.isEmpty else { continue }
                let entries = bucketMeals.map { "\($0.name) \(Int(($0.energy?.kilocalories ?? 0).rounded()))kcal" }
                lines.append("\(bucket.rawValue): \(entries.joined(separator: "; "))")
            }
        } else {
            lines.append("meals=none")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Range

    private func rangeBlock(endingAt endDay: HelmDay, lookbackDays: Int) async throws -> String {
        let startDay = endDay.adding(days: -(lookbackDays - 1))
        let engine = NutritionEngine(persistence: store, calendar: calendar, cutoff: cutoff)

        var lines: [String] = [
            "query=range start=\(startDay.formatted) end=\(endDay.formatted) days=\(lookbackDays)"
        ]

        // Per-day intake summary.
        var totalKcal = 0.0
        var dayCount = 0
        var latestEstimatedTDEE: Double?
        var latestTrendWeight: Double?
        var latestIntakeAvg: Double?
        for offset in 0 ..< lookbackDays {
            let day = startDay.adding(days: offset)
            let snapshot = await engine.snapshot(for: day, prescriptionSummary: nil, now: Date())
            let logged = snapshot.actual?.totalEnergy?.kilocalories ?? 0
            if logged > 0 {
                lines.append(
                    "\(day.formatted) \(format(logged))kcal P\(Int((snapshot.actual?.totalProteinGrams ?? 0).rounded()))g"
                )
                totalKcal += logged
                dayCount += 1
            }
            if let tdee = snapshot.trend.estimatedTDEEKcal { latestEstimatedTDEE = tdee }
            if let tw = snapshot.trend.smoothedTrendWeightKg { latestTrendWeight = tw }
            if let ia = snapshot.trend.weeklyIntakeAverageKcal { latestIntakeAvg = ia }
        }
        if dayCount > 0 {
            lines.append("avg_kcal=\(format(totalKcal / Double(dayCount))) over \(dayCount) logged days")
        }

        // Trend snapshot from latest available.
        if let tdee = latestEstimatedTDEE {
            lines.append("estimated_tdee=\(format(tdee))kcal")
        }
        if let trendWeight = latestTrendWeight {
            lines.append("trend_weight=\(format(trendWeight))kg")
        }
        if let intakeAvg = latestIntakeAvg {
            lines.append("weekly_intake_avg=\(format(intakeAvg))kcal")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Weekly Budget

    private func weeklyBudgetBlock(asOf day: HelmDay) async -> String {
        let engine = NutritionEngine(persistence: store, calendar: calendar, cutoff: cutoff)
        guard let budget = try? await engine.weeklyBudget(for: day, prescriptionSummary: nil) else {
            return "query=weeklyBudget error=unavailable"
        }

        var lines: [String] = [
            "query=weeklyBudget week_start=\(budget.weekStart.formatted)",
            "weekly_tgt_kcal=\(budget.targetCaloriesKcal)",
            "consumed_kcal=\(budget.consumedCaloriesKcal)",
            "remaining_kcal=\(budget.remainingCaloriesKcal)"
        ]
        if budget.excessCaloriesKcal > 0 {
            lines.append("excess_kcal=\(budget.excessCaloriesKcal)")
        }

        for day in budget.days {
            let stateTag = day.isProvisional ? " [provisional]" : ""
            let consumedNote = day.consumedCaloriesKcal.map { " (consumed \($0))" } ?? ""
            lines.append(
                "\(day.day.formatted) | \(day.demand.rawValue) | eat_to=\(day.eatToCaloriesKcal)kcal planned=\(day.plannedCaloriesKcal)kcal | P\(day.proteinGrams)g C\(day.carbohydrateGrams)g F\(day.fatGrams)g\(stateTag)\(consumedNote)"
            )
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func parseDay(_ raw: String?) -> HelmDay? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return HelmDay(year: year, month: month, day: day)
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}