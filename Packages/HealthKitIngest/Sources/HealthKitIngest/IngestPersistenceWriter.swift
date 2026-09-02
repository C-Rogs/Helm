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
            priorDayTRIMP: existing?.priorDayTRIMP,
            stepCount: patch.stepCount ?? existing?.stepCount,
            restingEnergyKcal: patch.restingEnergyKcal ?? existing?.restingEnergyKcal
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
             .activeEnergy, .dietaryEnergy, .dietaryProtein, .dietaryCarbohydrate, .dietaryFat,
             .stepCount, .basalEnergy:
            try applyQuantityDelta(delta)
            families.insert(delta.kind.metricFamily)
        case .sleep:
            try applySleepDelta(delta)
            families.insert(.sleep)
        case .bodyMass:
            try applyBodyMassDelta(delta)
            families.insert(.bodyComposition)
        case .bodyFatPercentage:
            try applyBodyFatDelta(delta)
            families.insert(.bodyComposition)
        case .workout:
            if !delta.trimpByTargetDay.isEmpty {
                try applyWorkoutTRIMP(delta.trimpByTargetDay)
                families.insert(.workouts)
            } else if !delta.addedWorkouts.isEmpty || !delta.deletedSampleIDs.isEmpty {
                families.insert(.workouts)
            }
            try applyWorkoutHistory(delta.addedWorkouts)
        }

        return families
    }

    private func applyQuantityDelta(_ delta: IngestDelta) throws {
        let mode = NutritionPreferencesStore.shared.mode()
        if mode == .helmOnly, delta.kind.metricFamily == .nutrition {
            return
        }

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

    func applyAuthoritativeCumulative(
        helmDay: HelmDay,
        stepCount: Int? = nil,
        activeEnergy: Energy? = nil,
        restingEnergyKcal: Double? = nil
    ) throws {
        let existing = try store.dailyMetrics.fetch(helmDay: helmDay)
        let merged = DailyMetrics(
            helmDay: helmDay,
            hrvSDNN: existing?.hrvSDNN,
            restingHeartRate: existing?.restingHeartRate,
            respiratoryRate: existing?.respiratoryRate,
            wristTemperatureDeltaCelsius: existing?.wristTemperatureDeltaCelsius,
            activeEnergy: activeEnergy ?? existing?.activeEnergy,
            dietaryEnergy: existing?.dietaryEnergy,
            dietaryProteinGrams: existing?.dietaryProteinGrams,
            dietaryCarbohydrateGrams: existing?.dietaryCarbohydrateGrams,
            dietaryFatGrams: existing?.dietaryFatGrams,
            priorDayTRIMP: existing?.priorDayTRIMP,
            stepCount: stepCount ?? existing?.stepCount,
            restingEnergyKcal: restingEnergyKcal ?? existing?.restingEnergyKcal
        )
        try store.dailyMetrics.upsert(merged)
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
        let mode = NutritionPreferencesStore.shared.mode()
        var affectedDays = Set<HelmDay>()
        for meal in meals {
            let existingMeals = try store.nutrition.fetchMeals(for: meal.helmDay)
            if DietarySourceMerger.shouldSkipExternalIngest(meal, existingMeals: existingMeals, mode: mode) {
                continue
            }
            try store.nutrition.upsertMeal(meal)
            affectedDays.insert(meal.helmDay)
        }

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
        for sample in delta.addedQuantitySamples {
            let kilograms = HealthKitDayAggregator.kilograms(from: sample)
            guard kilograms > 1 else { continue }
            let helmDay = HelmDay.day(for: sample.start, cutoff: cutoff, calendar: calendar)
            try store.bodyComposition.mergeBodyMass(
                helmDay: helmDay,
                massKg: kilograms,
                measuredAt: sample.start,
                sampleID: sample.id
            )
        }
    }

    private func applyBodyFatDelta(_ delta: IngestDelta) throws {
        for sample in delta.addedQuantitySamples {
            guard let percent = BodyFatPercent.storedPercent(fromHealthKitPercentUnit: sample.value) else {
                continue
            }
            let measuredAt = max(sample.start, sample.end)
            let helmDay = HelmDay.day(for: measuredAt, cutoff: cutoff, calendar: calendar)
            try store.bodyComposition.mergeBodyFat(
                helmDay: helmDay,
                bodyFatPercentage: percent,
                measuredAt: measuredAt
            )
        }
    }

    private func applyWorkoutTRIMP(_ trimpByTargetDay: [HelmDay: Double]) throws {
        for (targetDay, addedTRIMP) in trimpByTargetDay {
            let existing = try store.dailyMetrics.fetch(helmDay: targetDay)
            let mergedTRIMP = (existing?.priorDayTRIMP ?? 0) + addedTRIMP
            let merged = DailyMetrics(
                helmDay: targetDay,
                hrvSDNN: existing?.hrvSDNN,
                restingHeartRate: existing?.restingHeartRate,
                respiratoryRate: existing?.respiratoryRate,
                wristTemperatureDeltaCelsius: existing?.wristTemperatureDeltaCelsius,
                activeEnergy: existing?.activeEnergy,
                dietaryEnergy: existing?.dietaryEnergy,
                dietaryProteinGrams: existing?.dietaryProteinGrams,
                dietaryCarbohydrateGrams: existing?.dietaryCarbohydrateGrams,
                dietaryFatGrams: existing?.dietaryFatGrams,
                priorDayTRIMP: mergedTRIMP,
                stepCount: existing?.stepCount,
                restingEnergyKcal: existing?.restingEnergyKcal
            )
            try store.dailyMetrics.upsert(merged)
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

    private func applyWorkoutHistory(_ workouts: [IngestWorkoutSample]) throws {
        for workout in workouts {
            guard IngestSampleFilter.shouldPersistToHistory(sourceBundleID: workout.sourceBundleID) else {
                continue
            }
            let hkUUID = workout.id.uuidString

            // Skip workouts with non-positive duration (defensive).
            guard workout.end > workout.start else { continue }

            _ = try store.workoutSessions.upsertHealthKitWorkout(
                hkUUID: hkUUID,
                title: workout.activityDisplayName,
                startedAt: workout.start,
                endedAt: workout.end,
                activityType: workout.activityDisplayName,
                activeEnergyKilocalories: workout.activeEnergyKilocalories,
                distanceMeters: workout.totalDistanceMeters,
                sourceBundleID: workout.sourceBundleID
            )
        }
    }
}
