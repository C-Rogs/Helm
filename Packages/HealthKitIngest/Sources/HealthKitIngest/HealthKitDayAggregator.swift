import Core
import Foundation
import NutritionKit

public enum HealthKitDayAggregator {
    public static func aggregateQuantity(
        kind: HealthKitSampleKind,
        samples: [IngestQuantitySample],
        calendar: Calendar,
        cutoff: DayCutoff = .default
    ) -> [AggregatedDailyPatch] {
        guard !samples.isEmpty else { return [] }

        var buckets: [HelmDay: [IngestQuantitySample]] = [:]
        for sample in samples {
            let day = HelmDay.day(for: sample.start, cutoff: cutoff, calendar: calendar)
            buckets[day, default: []].append(sample)
        }

        return buckets.map { helmDay, daySamples in
            var patch = AggregatedDailyPatch(helmDay: helmDay)
            switch kind {
            case .hrvSDNN:
                let values = daySamples.map(\.value)
                let average = values.reduce(0, +) / Double(values.count)
                patch.hrvSDNN = DurationMs(milliseconds: Int(average.rounded()))
            case .restingHeartRate:
                let values = daySamples.map(\.value)
                let average = values.reduce(0, +) / Double(values.count)
                patch.restingHeartRate = Int(average.rounded())
            case .respiratoryRate:
                let values = daySamples.map(\.value)
                patch.respiratoryRate = values.reduce(0, +) / Double(values.count)
            case .wristTemperature:
                let values = daySamples.map(\.value)
                patch.wristTemperatureDeltaCelsius = values.reduce(0, +) / Double(values.count)
            case .activeEnergy:
                patch.activeEnergy = Energy(kilocalories: sumKilocalories(daySamples))
            case .dietaryEnergy:
                patch.dietaryEnergy = Energy(kilocalories: sumKilocalories(daySamples))
            case .dietaryProtein:
                patch.dietaryProteinGrams = sumGrams(daySamples)
            case .dietaryCarbohydrate:
                patch.dietaryCarbohydrateGrams = sumGrams(daySamples)
            case .dietaryFat:
                patch.dietaryFatGrams = sumGrams(daySamples)
            case .bodyMass, .sleep, .workout:
                break
            }
            return patch
        }
    }

    public static func sleepRecords(
        from samples: [IngestSleepSample],
        calendar: Calendar,
        cutoff: DayCutoff = .default
    ) -> [SleepRecord] {
        samples
            .filter(\.isAsleep)
            .map { sample in
                SleepRecord(
                    id: sample.id,
                    start: sample.start,
                    end: sample.end,
                    helmDay: SleepRecord.helmDay(forStart: sample.start, cutoff: cutoff, calendar: calendar),
                    sourceBundleID: sample.sourceBundleID
                )
            }
    }

    public static func mealDrafts(
        from samples: [IngestQuantitySample],
        macroKind: HealthKitSampleKind,
        calendar: Calendar,
        cutoff: DayCutoff = .default
    ) -> [IngestMealDraft] {
        samples.map { sample in
            let helmDay = HelmDay.day(for: sample.start, cutoff: cutoff, calendar: calendar)
            var energy: Energy?
            var protein: Double?
            var carbs: Double?
            var fat: Double?

            switch macroKind {
            case .dietaryEnergy:
                energy = Energy(kilocalories: kilocalories(from: sample))
            case .dietaryProtein:
                protein = sample.value
            case .dietaryCarbohydrate:
                carbs = sample.value
            case .dietaryFat:
                fat = sample.value
            default:
                break
            }

            return IngestMealDraft(
                id: sample.id,
                helmDay: helmDay,
                loggedAt: sample.start,
                energy: energy,
                proteinGrams: protein,
                carbohydrateGrams: carbs,
                fatGrams: fat,
                externalSampleID: sample.id.uuidString.lowercased()
            )
        }
    }

    public static func bodyCompositionRecords(
        from samples: [IngestQuantitySample],
        calendar: Calendar,
        cutoff: DayCutoff = .default
    ) -> [BodyComposition] {
        samples.compactMap { sample in
            let kilograms = kilograms(from: sample)
            guard kilograms > 1 else { return nil }
            let helmDay = HelmDay.day(for: sample.start, cutoff: cutoff, calendar: calendar)
            return BodyComposition(
                id: sample.id,
                helmDay: helmDay,
                mass: Mass(kilograms: kilograms),
                measuredAt: sample.start
            )
        }
    }

    public static func mergeMealDrafts(_ drafts: [IngestMealDraft]) -> [MealRecord] {
        var merged: [String: IngestMealDraft] = [:]
        for draft in drafts {
            if var existing = merged[draft.externalSampleID] {
                existing = mergeDraft(existing, with: draft)
                merged[draft.externalSampleID] = existing
            } else {
                merged[draft.externalSampleID] = draft
            }
        }

        return merged.values.map { draft in
            MealRecord(
                id: draft.id,
                helmDay: draft.helmDay,
                name: "HealthKit meal",
                loggedAt: draft.loggedAt,
                energy: draft.energy,
                proteinGrams: draft.proteinGrams,
                carbohydrateGrams: draft.carbohydrateGrams,
                fatGrams: draft.fatGrams,
                source: .healthKit,
                externalSampleID: draft.externalSampleID
            )
        }
    }

    public static func nutritionDay(
        from meals: [MealRecord],
        helmDay: HelmDay
    ) -> NutritionDay {
        let dayMeals = meals.filter { $0.helmDay == helmDay }
        let totalEnergy = sumOptional(dayMeals.compactMap(\.energy))
        let protein = sumOptionalDoubles(dayMeals.compactMap(\.proteinGrams))
        let carbs = sumOptionalDoubles(dayMeals.compactMap(\.carbohydrateGrams))
        let fat = sumOptionalDoubles(dayMeals.compactMap(\.fatGrams))
        let explicitAlcoholKcal = MacroGapCalculator.explicitAlcoholKilocalories(from: dayMeals)

        let macroGap: Double?
        if let totalEnergy, let protein, let carbs, let fat {
            macroGap = MacroGapCalculator.macroGap(
                totalEnergyKcal: totalEnergy.kilocalories,
                proteinGrams: protein,
                carbohydrateGrams: carbs,
                fatGrams: fat,
                explicitAlcoholKilocalories: explicitAlcoholKcal
            )
        } else if let totalEnergy {
            let reconstructed = (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
            let gap = totalEnergy.kilocalories - reconstructed - explicitAlcoholKcal
            macroGap = gap > 1 ? gap : nil
        } else {
            macroGap = nil
        }

        return NutritionDay(
            helmDay: helmDay,
            totalEnergy: totalEnergy,
            totalProteinGrams: protein,
            totalCarbohydrateGrams: carbs,
            totalFatGrams: fat,
            macroGapKilocalories: macroGap
        )
    }

    private static func mergeDraft(_ lhs: IngestMealDraft, with rhs: IngestMealDraft) -> IngestMealDraft {
        IngestMealDraft(
            id: lhs.id,
            helmDay: lhs.helmDay,
            loggedAt: lhs.loggedAt,
            energy: rhs.energy ?? lhs.energy,
            proteinGrams: rhs.proteinGrams ?? lhs.proteinGrams,
            carbohydrateGrams: rhs.carbohydrateGrams ?? lhs.carbohydrateGrams,
            fatGrams: rhs.fatGrams ?? lhs.fatGrams,
            externalSampleID: lhs.externalSampleID
        )
    }

    private static func sumKilocalories(_ samples: [IngestQuantitySample]) -> Double {
        samples.reduce(0) { partial, sample in
            partial + kilocalories(from: sample)
        }
    }

    private static func sumGrams(_ samples: [IngestQuantitySample]) -> Double {
        samples.reduce(0) { $0 + $1.value }
    }

    private static func kilocalories(from sample: IngestQuantitySample) -> Double {
        switch sample.unitSymbol {
        case "kcal":
            sample.value
        case "Cal":
            sample.value
        case "kJ":
            Energy(kilojoules: sample.value).kilocalories
        default:
            sample.value
        }
    }

    private static func kilograms(from sample: IngestQuantitySample) -> Double {
        switch sample.unitSymbol {
        case "kg":
            sample.value
        case "lb":
            Mass(pounds: sample.value).kilograms
        default:
            sample.value
        }
    }

    private static func sumOptional(_ values: [Energy]) -> Energy? {
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0) { $0 + $1.kilocalories }
        return Energy(kilocalories: total)
    }

    private static func sumOptionalDoubles(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }
}
