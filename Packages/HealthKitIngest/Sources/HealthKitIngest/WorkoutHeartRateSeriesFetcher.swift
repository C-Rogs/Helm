import Core
import Foundation
import HealthKit

/// Builds finish-chart HR series from HealthKit (authoritative), not the live Train buffer.
public struct WorkoutHeartRateSeriesFetcher: Sendable {
    private let store: any HealthKitStoreClient
    private let minIntervalSeconds: Int

    public init(
        store: any HealthKitStoreClient = LiveHealthKitStore(),
        minIntervalSeconds: Int = 5
    ) {
        self.store = store
        self.minIntervalSeconds = max(1, minIntervalSeconds)
    }

    /// Maps dated BPM readings into session-relative samples with dedupe interval.
    public static func timelineSamples(
        readings: [(date: Date, bpm: Int)],
        startedAt: Date,
        minIntervalSeconds: Int = 5
    ) -> [SessionHeartRateSample] {
        let interval = max(1, minIntervalSeconds)
        var buffer = SessionHeartRateBuffer(minIntervalSeconds: interval)
        for reading in readings.sorted(by: { $0.date < $1.date }) {
            guard reading.bpm > 0 else { continue }
            let offset = Int(reading.date.timeIntervalSince(startedAt))
            guard offset >= 0 else { continue }
            buffer.record(bpm: reading.bpm, offsetSeconds: offset)
        }
        return buffer.samples
    }

    public func timelineSamples(startedAt: Date, endedAt: Date) async throws -> [SessionHeartRateSample] {
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: startedAt,
            end: endedAt,
            options: .strictStartDate
        )
        let samples = try await store.fetchSamples(
            sampleType: heartRateType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        let readings: [(Date, Int)] = samples.compactMap { sample in
            guard let quantity = sample as? HKQuantitySample else { return nil }
            let bpm = Int(quantity.quantity.doubleValue(for: unit).rounded())
            guard bpm > 0 else { return nil }
            return (quantity.startDate, bpm)
        }
        return Self.timelineSamples(
            readings: readings,
            startedAt: startedAt,
            minIntervalSeconds: minIntervalSeconds
        )
    }

    /// After builders finish, HealthKit may need a beat to index Watch-synced samples.
    /// Retries then falls back to live buffer for chart only (never for TRIMP).
    public func timelineSamplesForFinishChart(
        startedAt: Date,
        endedAt: Date,
        liveFallback: [SessionHeartRateSample],
        retryDelaysSeconds: [TimeInterval] = [0, 0.6, 1.5]
    ) async -> [SessionHeartRateSample] {
        for (index, delay) in retryDelaysSeconds.enumerated() {
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            if let series = try? await timelineSamples(startedAt: startedAt, endedAt: endedAt),
               !series.isEmpty {
                return series
            }
            _ = index
        }
        return liveFallback
    }
}
