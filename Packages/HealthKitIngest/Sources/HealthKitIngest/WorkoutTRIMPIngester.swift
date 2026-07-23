import Core
import Foundation
import HealthKit
import Persistence

/// Fetches workout heart-rate samples and computes Edwards TRIMP patches.
public struct WorkoutTRIMPIngester: Sendable {
    private let store: any HealthKitStoreClient
    private let persistence: PersistenceStore
    private let calendar: Calendar
    private let cutoff: DayCutoff
    private let defaultRestingHeartRate: Double

    public init(
        store: any HealthKitStoreClient,
        persistence: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default,
        defaultRestingHeartRate: Double = 60
    ) {
        self.store = store
        self.persistence = persistence
        self.calendar = calendar
        self.cutoff = cutoff
        self.defaultRestingHeartRate = defaultRestingHeartRate
    }

    public func trimpByTargetDay(for workouts: [IngestWorkoutSample]) async throws -> [HelmDay: Double] {
        var results: [WorkoutTRIMPCalculator.Result] = []

        for workout in workouts {
            let heartRates = try await fetchHeartRateSamples(for: workout)
            let workoutDay = HelmDay.day(for: workout.end, cutoff: cutoff, calendar: calendar)
            let restingHR = restingHeartRate(for: workoutDay)
            if let result = WorkoutTRIMPCalculator.trimp(
                for: workout,
                heartRateSamples: heartRates,
                restingHeartRate: restingHR,
                calendar: calendar,
                cutoff: cutoff
            ) {
                results.append(result)
            }
        }

        return WorkoutTRIMPCalculator.mergedTRIMPByTargetDay(results)
    }

    private func restingHeartRate(for workoutDay: HelmDay) -> Double {
        if let stored = try? persistence.dailyMetrics.fetch(helmDay: workoutDay)?.restingHeartRate {
            return Double(stored)
        }
        return defaultRestingHeartRate
    }

    private func fetchHeartRateSamples(for workout: IngestWorkoutSample) async throws -> [Double] {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: workout.start,
            end: workout.end,
            options: .strictStartDate
        )
        let samples = try await store.fetchSamples(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit
        )

        let unit = HKUnit.count().unitDivided(by: .minute())
        return samples.compactMap { sample -> Double? in
            guard let quantitySample = sample as? HKQuantitySample else { return nil }
            return quantitySample.quantity.doubleValue(for: unit)
        }
    }
}
