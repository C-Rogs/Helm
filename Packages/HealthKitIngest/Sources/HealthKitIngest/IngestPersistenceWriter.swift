import Core
import Foundation
import Persistence

public enum DailyMetricsMerge {
    public static func apply(patch: AggregatedDailyPatch, to existing: DailyMetrics?) -> DailyMetrics {
        DailyMetrics(
            helmDay: patch.helmDay,
            hrvSDNN: patch.hrvSDNN ?? existing?.hrvSDNN,
            restingHeartRate: patch.restingHeartRate ?? existing?.restingHeartRate,
            respiratoryRate: patch.respiratoryRate ?? existing?.respiratoryRate,
            wristTemperatureDeltaCelsius: patch.wristTemperatureDeltaCelsius ?? existing?.wristTemperatureDeltaCelsius,
            activeEnergy: patch.activeEnergy ?? existing?.activeEnergy,
            dietaryEnergy: patch.dietaryEnergy ?? existing?.dietaryEnergy,
            dietaryProteinGrams: patch.dietaryProteinGrams ?? existing?.dietaryProteinGrams,
            dietaryCarbohydrateGrams: patch.dietaryCarbohydrateGrams ?? existing?.dietaryCarbohydrateGrams,
            dietaryFatGrams: patch.dietaryFatGrams ?? existing?.dietaryFatGrams,
            priorDayTRIMP: existing?.priorDayTRIMP
        )
    }
}

public struct IngestPersistenceWriter: Sendable {
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

    public func apply(delta: IngestDelta) throws -> Set<HealthKitMetricFamily> {
        var families: Set<HealthKitMetricFamily> = []

        if !delta.deletedSampleIDs.isEmpty {
            try applyDeletions(delta)
            families.insert(delta.kind.metricFamily)
        }

        switch delta.kind {
        case .hrvSDNN, .restingHeartRate, .respiratoryRate, .wristTemperature,
             .activeEnergy, .dietaryEnergy, .dietaryProtein, .dietaryCarbohydrate, .dietaryFat:
            try applyQuantityDelta(delta)
            families.insert(delta.kind.metricFamily)
        case .sleep:
            try applySleepDelta(delta)
            families.insert(.sleep)
        case .bodyMass:
            try applyBodyMassDelta(delta)
            families.insert(.bodyComposition)
        case .workout:
            if !delta.addedWorkouts.isEmpty || !delta.deletedSampleIDs.isEmpty {
                families.insert(.workouts)
            }
        }

        return families
    }

    private func applyQuantityDelta(_ delta: IngestDelta) throws {
        let patches = HealthKitDayAggregator.aggregateQuantity(
            kind: delta.kind,
            samples: delta.addedQuantitySamples,
            calendar: calendar,
            cutoff: cutoff
        )

        for patch in patches {
            let existing = try store.dailyMetrics.fetch(helmDay: patch.helmDay)
            let merged = DailyMetricsMerge.apply(patch: patch, to: existing)
            try store.dailyMetrics.upsert(merged)
        }

        if delta.kind.metricFamily == .nutrition {
            try applyNutritionMeals(delta)
        }
    }

    private func applyNutritionMeals(_ delta: IngestDelta) throws {
        guard [.dietaryEnergy, .dietaryProtein, .dietaryCarbohydrate, .dietaryFat].contains(delta.kind) else {
            return
        }

        let drafts = HealthKitDayAggregator.mealDrafts(
            from: delta.addedQuantitySamples,
            macroKind: delta.kind,
            calendar: calendar,
            cutoff: cutoff
        )
        let meals = HealthKitDayAggregator.mergeMealDrafts(drafts)
        for meal in meals {
            try store.nutrition.upsertMeal(meal)
        }

        let affectedDays = Set(meals.map(\.helmDay))
        for helmDay in affectedDays {
            let dayMeals = try store.nutrition.fetchMeals(for: helmDay)
            let nutritionDay = HealthKitDayAggregator.nutritionDay(from: dayMeals, helmDay: helmDay)
            try store.nutrition.upsertDay(nutritionDay)
        }
    }

    private func applySleepDelta(_ delta: IngestDelta) throws {
        let records = HealthKitDayAggregator.sleepRecords(
            from: delta.addedSleepSamples,
            calendar: calendar,
            cutoff: cutoff
        )
        for record in records {
            try store.sleep.upsert(record)
        }
    }

    private func applyBodyMassDelta(_ delta: IngestDelta) throws {
        let records = HealthKitDayAggregator.bodyCompositionRecords(
            from: delta.addedQuantitySamples,
            calendar: calendar,
            cutoff: cutoff
        )
        for record in records {
            try store.bodyComposition.upsert(record)
        }
    }

    private func applyDeletions(_ delta: IngestDelta) throws {
        for sampleID in delta.deletedSampleIDs {
            let key = sampleID.uuidString.lowercased()
            switch delta.kind.metricFamily {
            case .nutrition:
                if let meal = try store.nutrition.fetchMeal(id: sampleID) {
                    try store.nutrition.deleteMeal(id: sampleID)
                    let remaining = try store.nutrition.fetchMeals(for: meal.helmDay)
                    if remaining.isEmpty {
                        try store.nutrition.deleteDay(helmDay: meal.helmDay)
                    } else {
                        let day = HealthKitDayAggregator.nutritionDay(from: remaining, helmDay: meal.helmDay)
                        try store.nutrition.upsertDay(day)
                    }
                }
            case .sleep:
                try store.sleep.delete(id: sampleID)
            case .bodyComposition:
                try store.bodyComposition.delete(id: sampleID)
            case .vitals, .activity, .workouts:
                _ = key
            }
        }
    }
}
