import CoachLLM
import Core
import Foundation
import Persistence

/// On-demand meal history lookups for coach meal_query.v1 (no 14-day context bloat).
public struct MealHistoryQueryService: Sendable {
    private let nutrition: NutritionRepository
    private let calendar: Calendar

    public init(store: PersistenceStore, calendar: Calendar = .current) {
        nutrition = store.nutrition
        self.calendar = calendar
    }

    public func run(_ payload: MealQueryPayload, now: Date = Date()) throws -> String {
        let today = HelmDay.day(for: now, calendar: calendar)
        switch payload.queryType {
        case .bucketOnDay:
            return try bucketOnDay(payload, today: today)
        case .usualForBucket:
            return try usualForBucket(payload, today: today)
        case .daySummary:
            return try daySummary(payload, today: today)
        }
    }

    private func bucketOnDay(_ payload: MealQueryPayload, today: HelmDay) throws -> String {
        guard let day = parseDay(payload.helmDay) ?? Optional(today) else {
            return "error=missing_helmDay"
        }
        guard let bucket = parseBucket(payload.bucket) else {
            return "error=missing_bucket"
        }
        let meals = try nutrition.fetchMeals(for: day).filter { $0.bucket == bucket }
        guard !meals.isEmpty else {
            return "query=bucketOnDay day=\(day.formatted) bucket=\(bucket.rawValue)\nmeals=none"
        }
        return formatMeals(
            header: "query=bucketOnDay day=\(day.formatted) bucket=\(bucket.rawValue)",
            meals: meals
        )
    }

    private func daySummary(_ payload: MealQueryPayload, today: HelmDay) throws -> String {
        guard let day = parseDay(payload.helmDay) ?? Optional(today) else {
            return "error=missing_helmDay"
        }
        let meals = try nutrition.fetchMeals(for: day)
        guard !meals.isEmpty else {
            return "query=daySummary day=\(day.formatted)\nmeals=none"
        }
        return formatMeals(header: "query=daySummary day=\(day.formatted)", meals: meals)
    }

    private func usualForBucket(_ payload: MealQueryPayload, today: HelmDay) throws -> String {
        guard let bucket = parseBucket(payload.bucket) else {
            return "error=missing_bucket"
        }
        let lookback = min(max(payload.lookbackDays ?? 30, 7), 90)
        var samples: [(HelmDay, [MealRecord])] = []
        for offset in 1 ... lookback {
            let day = today.adding(days: -offset)
            let meals = try nutrition.fetchMeals(for: day).filter { $0.bucket == bucket }
            if !meals.isEmpty {
                samples.append((day, meals))
            }
            if samples.count >= 8 { break }
        }
        guard !samples.isEmpty else {
            return "query=usualForBucket bucket=\(bucket.rawValue) lookback=\(lookback)\nmeals=none"
        }

        var lines = [
            "query=usualForBucket bucket=\(bucket.rawValue) lookback=\(lookback) samples=\(samples.count)"
        ]
        let avgKcal = samples.map { sample in
            sample.1.reduce(0.0) { $0 + ($1.energy?.kilocalories ?? 0) }
        }.reduce(0, +) / Double(samples.count)
        let avgP = samples.map { sample in
            sample.1.reduce(0.0) { $0 + ($1.proteinGrams ?? 0) }
        }.reduce(0, +) / Double(samples.count)
        let avgC = samples.map { sample in
            sample.1.reduce(0.0) { $0 + ($1.carbohydrateGrams ?? 0) }
        }.reduce(0, +) / Double(samples.count)
        let avgF = samples.map { sample in
            sample.1.reduce(0.0) { $0 + ($1.fatGrams ?? 0) }
        }.reduce(0, +) / Double(samples.count)
        lines.append(
            "avg_kcal=\(Int(avgKcal.rounded())) protein_g=\(Int(avgP.rounded())) carbs_g=\(Int(avgC.rounded())) fat_g=\(Int(avgF.rounded()))"
        )
        for (day, meals) in samples.prefix(5) {
            let names = meals.map(\.name).joined(separator: ", ")
            let kcal = Int(meals.reduce(0.0) { $0 + ($1.energy?.kilocalories ?? 0) }.rounded())
            lines.append("\(day.formatted): \(names) (\(kcal) kcal)")
        }
        return lines.joined(separator: "\n")
    }

    private func formatMeals(header: String, meals: [MealRecord]) -> String {
        var lines = [header]
        for meal in meals {
            let kcal = Int((meal.energy?.kilocalories ?? 0).rounded())
            let p = Int((meal.proteinGrams ?? 0).rounded())
            let c = Int((meal.carbohydrateGrams ?? 0).rounded())
            let f = Int((meal.fatGrams ?? 0).rounded())
            lines.append(
                "id=\(meal.id.uuidString.lowercased()) bucket=\(meal.bucket.rawValue) name=\(meal.name) kcal=\(kcal) P=\(p) C=\(c) F=\(f)"
            )
        }
        return lines.joined(separator: "\n")
    }

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

    private func parseBucket(_ raw: String?) -> MealBucket? {
        guard let raw else { return nil }
        return MealBucket(rawValue: raw.lowercased())
    }
}
