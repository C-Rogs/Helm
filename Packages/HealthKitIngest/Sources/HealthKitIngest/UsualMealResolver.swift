import Core
import Foundation
import Persistence

/// Resolves a usual meal for an empty bucket, split by weekday vs weekend.
public struct UsualMealResolver: Sendable {
    public static let lookbackDays = 45
    public static let maxSamples = 8
    public static let snackMinimumSamples = 2

    private let nutrition: NutritionRepository
    private let mealTemplates: MealTemplateRepository
    private let calendar: Calendar

    public init(store: PersistenceStore, calendar: Calendar = .current) {
        nutrition = store.nutrition
        mealTemplates = store.mealTemplates
        self.calendar = calendar
    }

    public func proposal(for bucket: MealBucket, on day: HelmDay) throws -> UsualMealProposal? {
        try proposal(for: bucket, on: day, samples: try matchingSamples(for: bucket, on: day))
    }

    public func proposal(
        for bucket: MealBucket,
        on day: HelmDay,
        samples: [UsualMealDaySample]
    ) throws -> UsualMealProposal? {
        let existing = try nutrition.fetchMeals(for: day).filter { $0.bucket == bucket }
        guard existing.isEmpty else { return nil }

        let templates = try mealTemplates.fetchAll().filter { $0.bucket == bucket }
        let targetIsWeekend = isWeekend(day)

        if bucket == .snacks, samples.count < Self.snackMinimumSamples {
            return nil
        }

        if let template = bestTemplate(templates, samples: samples) {
            return proposal(from: template)
        }

        if let latest = samples.first {
            return proposal(copying: latest.meals, from: latest.day, bucket: bucket)
        }

        if !targetIsWeekend, bucket != .snacks, templates.count == 1, let template = templates.first {
            return proposal(from: template)
        }

        return nil
    }

    /// Matching weekday/weekend days with a non-empty bucket, most recent first.
    public func matchingSamples(for bucket: MealBucket, on day: HelmDay) throws -> [UsualMealDaySample] {
        let lookbackStart = day.adding(days: -Self.lookbackDays, calendar: calendar)
        let through = day.adding(days: -1, calendar: calendar)
        guard lookbackStart <= through else { return [] }

        let meals = try nutrition.fetchMealsInRange(from: lookbackStart, through: through)
            .filter { $0.bucket == bucket }
        let grouped = Dictionary(grouping: meals, by: \.helmDay)
        let wantWeekend = isWeekend(day)

        var samples: [UsualMealDaySample] = []
        for offset in 1 ... Self.lookbackDays {
            let sampleDay = day.adding(days: -offset, calendar: calendar)
            guard isWeekend(sampleDay) == wantWeekend else { continue }
            guard let dayMeals = grouped[sampleDay], !dayMeals.isEmpty else { continue }
            let ordered = dayMeals.sorted { $0.loggedAt < $1.loggedAt }
            samples.append(UsualMealDaySample(day: sampleDay, meals: ordered))
            if samples.count >= Self.maxSamples { break }
        }
        return samples
    }

    public func isWeekend(_ day: HelmDay) -> Bool {
        guard let date = calendar.date(from: day.dateComponents()) else { return false }
        return calendar.isDateInWeekend(date)
    }

    private func bestTemplate(
        _ templates: [MealTemplate],
        samples: [UsualMealDaySample]
    ) -> MealTemplate? {
        guard !templates.isEmpty else { return nil }
        let scored: [(MealTemplate, Int)] = templates.map { template in
            let score = samples.filter { sample in
                sample.meals.contains { meal in
                    meal.name.compare(
                        template.name,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
                }
            }.count
            return (template, score)
        }
        let matches = scored.filter { $0.1 > 0 }
        guard let best = matches.max(by: { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.updatedAt < rhs.0.updatedAt
        }) else {
            return nil
        }
        return best.0
    }

    private func proposal(from template: MealTemplate) -> UsualMealProposal {
        let kcal = Int(template.lineItems.reduce(0) { $0 + $1.caloriesKcal }.rounded())
        return UsualMealProposal(
            bucket: template.bucket,
            displayName: template.name,
            energyKcal: kcal,
            source: .template(template)
        )
    }

    private func proposal(
        copying meals: [MealRecord],
        from day: HelmDay,
        bucket: MealBucket
    ) -> UsualMealProposal {
        let names = meals.map(\.name).filter { !$0.isEmpty }
        let displayName: String
        if names.isEmpty {
            displayName = bucket.displayName
        } else if names.count == 1 {
            displayName = names[0]
        } else {
            displayName = names.joined(separator: ", ")
        }
        let kcal = Int(
            meals.reduce(0.0) { $0 + ($1.energy?.kilocalories ?? 0) }.rounded()
        )
        return UsualMealProposal(
            bucket: bucket,
            displayName: displayName,
            energyKcal: kcal,
            source: .copy(from: day)
        )
    }
}

public struct UsualMealDaySample: Sendable, Equatable {
    public let day: HelmDay
    public let meals: [MealRecord]
}
