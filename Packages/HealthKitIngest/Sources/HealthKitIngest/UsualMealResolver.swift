import Core
import Foundation
import Persistence

/// Resolves a repeated usual meal for an empty bucket, split by weekday vs weekend.
public struct UsualMealResolver: Sendable {
    public static let lookbackDays = 45
    public static let maxSamples = 8
    public static let minimumSamples = 3

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
        guard samples.count >= Self.minimumSamples else {
            return nil
        }

        if let template = bestTemplate(templates, samples: samples) {
            return proposal(from: template)
        }

        if let recurring = bestRecurringSample(in: samples) {
            return proposal(copying: recurring.meals, from: recurring.day, bucket: bucket)
        }

        return nil
    }

    /// Matching weekday/weekend days with a non-empty bucket, most recent first.
    public func matchingSamples(for bucket: MealBucket, on day: HelmDay) throws -> [UsualMealDaySample] {
        let lookbackStart = day.adding(days: -Self.lookbackDays, calendar: calendar)
        let through = day.adding(days: -1, calendar: calendar)
        guard lookbackStart <= through else { return [] }

        // HealthKit imports are backfill, not intentional usual meals - exclude them
        // so MFP/etc. rows never drive "Usual HealthKit meal?" nudges.
        let meals = try nutrition.fetchMealsInRange(from: lookbackStart, through: through)
            .filter { $0.bucket == bucket && $0.source != .healthKit }
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
        let matches = scored.filter {
            Self.hasUsualSupport(matchCount: $0.1, sampleCount: samples.count)
        }
        guard let best = matches.max(by: { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0.updatedAt < rhs.0.updatedAt
        }) else {
            return nil
        }
        return best.0
    }

    private func bestRecurringSample(in samples: [UsualMealDaySample]) -> UsualMealDaySample? {
        var grouped: [String: (count: Int, sample: UsualMealDaySample, firstIndex: Int)] = [:]

        for (index, sample) in samples.enumerated() {
            guard let identity = Self.mealIdentity(for: sample.meals) else { continue }
            if let current = grouped[identity] {
                grouped[identity] = (
                    count: current.count + 1,
                    sample: current.sample,
                    firstIndex: current.firstIndex
                )
            } else {
                grouped[identity] = (count: 1, sample: sample, firstIndex: index)
            }
        }

        return grouped.values
            .filter { Self.hasUsualSupport(matchCount: $0.count, sampleCount: samples.count) }
            .max { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count < rhs.count
                }
                return lhs.firstIndex > rhs.firstIndex
            }?
            .sample
    }

    private static func hasUsualSupport(matchCount: Int, sampleCount: Int) -> Bool {
        matchCount >= minimumSamples && matchCount * 2 >= sampleCount
    }

    private static func mealIdentity(for meals: [MealRecord]) -> String? {
        let names = meals.compactMap { meal -> String? in
            let normalized = meal.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            return normalized.isEmpty ? nil : normalized
        }
        guard !names.isEmpty else { return nil }
        return Array(Set(names)).sorted().joined(separator: "|")
    }

    /// Preserve first-seen order; drop case-insensitive duplicates.
    static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for name in names {
            let key = name.lowercased()
            guard seen.insert(key).inserted else { continue }
            unique.append(name)
        }
        return unique
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
        let names = Self.uniqueNames(meals.map(\.name).filter { !$0.isEmpty })
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
