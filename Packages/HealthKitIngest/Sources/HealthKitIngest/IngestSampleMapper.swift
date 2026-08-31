import Core
import Foundation
import HealthKit

enum IngestSampleMapper {
    static func quantitySamples(
        from samples: [HKSample],
        kind: HealthKitSampleKind,
        ownBundleID: String
    ) -> [IngestQuantitySample] {
        let unit = quantityUnit(for: kind)
        return samples.compactMap { sample -> IngestQuantitySample? in
            guard let quantitySample = sample as? HKQuantitySample else { return nil }
            let bundleID = quantitySample.sourceRevision.source.bundleIdentifier
            guard IngestSampleFilter.shouldIngest(sourceBundleID: bundleID, ownBundleID: ownBundleID) else {
                return nil
            }
            guard quantitySample.quantity.is(compatibleWith: unit) else { return nil }
            return IngestQuantitySample(
                id: quantitySample.uuid,
                start: quantitySample.startDate,
                end: quantitySample.endDate,
                value: quantitySample.quantity.doubleValue(for: unit),
                unitSymbol: unit.unitString,
                sourceBundleID: bundleID
            )
        }
    }

    private static func quantityUnit(for kind: HealthKitSampleKind) -> HKUnit {
        switch kind {
        case .hrvSDNN:
            .secondUnit(with: .milli)
        case .restingHeartRate:
            .count().unitDivided(by: .minute())
        case .respiratoryRate:
            .count().unitDivided(by: .minute())
        case .wristTemperature:
            .degreeCelsius()
        case .activeEnergy, .dietaryEnergy, .basalEnergy:
            .kilocalorie()
        case .dietaryProtein, .dietaryCarbohydrate, .dietaryFat:
            .gram()
        case .bodyMass:
            .gramUnit(with: .kilo)
        case .bodyFatPercentage:
            .percent()
        case .stepCount:
            .count()
        case .sleep, .workout:
            .count()
        }
    }

    static func sleepSamples(
        from samples: [HKSample],
        ownBundleID: String
    ) -> [IngestSleepSample] {
        samples.compactMap { sample -> IngestSleepSample? in
            guard let categorySample = sample as? HKCategorySample else { return nil }
            let bundleID = categorySample.sourceRevision.source.bundleIdentifier
            guard IngestSampleFilter.shouldIngest(sourceBundleID: bundleID, ownBundleID: ownBundleID) else {
                return nil
            }
            guard let stage = sleepStage(for: categorySample.value) else { return nil }
            return IngestSleepSample(
                id: categorySample.uuid,
                start: categorySample.startDate,
                end: categorySample.endDate,
                stage: stage,
                sourceBundleID: bundleID
            )
        }
    }

    static func sleepStage(for hkValue: Int) -> SleepAnalysisStage? {
        switch hkValue {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            .inBed
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            .awake
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            .asleepUnspecified
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            .asleepCore
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            .asleepDeep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            .asleepREM
        default:
            nil
        }
    }

    static func workoutSamples(
        from samples: [HKSample],
        ownBundleID: String
    ) -> [IngestWorkoutSample] {
        samples.compactMap { sample -> IngestWorkoutSample? in
            guard let workout = sample as? HKWorkout else { return nil }
            let bundleID = workout.sourceRevision.source.bundleIdentifier
            guard IngestSampleFilter.shouldIngest(sourceBundleID: bundleID, ownBundleID: ownBundleID) else {
                return nil
            }
            return IngestWorkoutSample(
                id: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                sourceBundleID: bundleID,
                activityTypeRawValue: workout.workoutActivityType.rawValue,
                activityDisplayName: WorkoutActivityTypeFormatter.displayName(for: workout.workoutActivityType),
                activeEnergyKilocalories: activeEnergyKcal(for: workout),
                totalDistanceMeters: totalDistanceMeters(for: workout)
            )
        }
    }

    private static func activeEnergyKcal(for workout: HKWorkout) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return nil
        }
        return workout.statistics(for: type)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
    }

    private static func totalDistanceMeters(for workout: HKWorkout) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
              let distance = workout.statistics(for: type)?.sumQuantity() else {
            return nil
        }
        return distance.doubleValue(for: .meter())
    }

    static func delta(
        kind: HealthKitSampleKind,
        addedSamples: [HKSample],
        deletedObjectIDs: [UUID],
        ownBundleID: String
    ) -> IngestDelta {
        switch kind {
        case .sleep:
            IngestDelta(
                kind: kind,
                addedSleepSamples: sleepSamples(from: addedSamples, ownBundleID: ownBundleID),
                deletedSampleIDs: deletedObjectIDs
            )
        case .workout:
            IngestDelta(
                kind: kind,
                addedWorkouts: workoutSamples(from: addedSamples, ownBundleID: ownBundleID),
                deletedSampleIDs: deletedObjectIDs
            )
        case .bodyMass, .hrvSDNN, .restingHeartRate, .respiratoryRate, .wristTemperature,
             .activeEnergy, .dietaryEnergy, .dietaryProtein, .dietaryCarbohydrate, .dietaryFat,
             .bodyFatPercentage, .stepCount, .basalEnergy:
            IngestDelta(
                kind: kind,
                addedQuantitySamples: quantitySamples(from: addedSamples, kind: kind, ownBundleID: ownBundleID),
                deletedSampleIDs: deletedObjectIDs
            )
        }
    }
}
