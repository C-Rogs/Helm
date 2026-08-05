import Core
import Foundation
import HealthKit
import Testing
@testable import HealthKitIngest

@Suite("WorkoutHeartRateSeriesFetcher")
struct WorkoutHeartRateSeriesFetcherTests {
    @Test("maps HK readings to session offsets with dedupe")
    func timelineMapping() {
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = WorkoutHeartRateSeriesFetcher.timelineSamples(
            readings: [
                (start.addingTimeInterval(0), 110),
                (start.addingTimeInterval(2), 110),
                (start.addingTimeInterval(6), 132),
                (start.addingTimeInterval(20), 140)
            ],
            startedAt: start,
            minIntervalSeconds: 5
        )
        #expect(samples.map(\.bpm) == [110, 132, 140])
        #expect(samples.map(\.offsetSeconds) == [0, 6, 20])
    }

    @Test("drops pre-start and non-positive BPM")
    func filters() {
        let start = Date(timeIntervalSince1970: 2_000)
        let samples = WorkoutHeartRateSeriesFetcher.timelineSamples(
            readings: [
                (start.addingTimeInterval(-5), 99),
                (start.addingTimeInterval(1), 0),
                (start.addingTimeInterval(3), 120)
            ],
            startedAt: start,
            minIntervalSeconds: 5
        )
        #expect(samples == [SessionHeartRateSample(offsetSeconds: 3, bpm: 120)])
    }

    @Test("fetches from store and builds timeline")
    func fetchFromStore() async throws {
        let start = Date(timeIntervalSince1970: 3_000)
        let end = start.addingTimeInterval(120)
        let heartRateType = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let hkSamples: [HKSample] = [
            HKQuantitySample(
                type: heartRateType,
                quantity: HKQuantity(unit: unit, doubleValue: 118),
                start: start.addingTimeInterval(10),
                end: start.addingTimeInterval(10)
            ),
            HKQuantitySample(
                type: heartRateType,
                quantity: HKQuantity(unit: unit, doubleValue: 145),
                start: start.addingTimeInterval(70),
                end: start.addingTimeInterval(70)
            )
        ]
        let mock = MockHealthKitStoreClient()
        mock.setSampleResults(hkSamples, for: heartRateType)
        let fetcher = WorkoutHeartRateSeriesFetcher(store: mock, minIntervalSeconds: 5)
        let series = try await fetcher.timelineSamples(startedAt: start, endedAt: end)
        #expect(series.map(\.bpm) == [118, 145])
        #expect(series.map(\.offsetSeconds) == [10, 70])
    }

    @Test("finish chart falls back to live buffer when HK empty")
    func finishFallback() async {
        let start = Date(timeIntervalSince1970: 4_000)
        let end = start.addingTimeInterval(60)
        let mock = MockHealthKitStoreClient()
        mock.setSampleResults([], for: HKQuantityType(.heartRate))
        let fetcher = WorkoutHeartRateSeriesFetcher(store: mock)
        let fallback = [SessionHeartRateSample(offsetSeconds: 5, bpm: 130)]
        let series = await fetcher.timelineSamplesForFinishChart(
            startedAt: start,
            endedAt: end,
            liveFallback: fallback,
            retryDelaysSeconds: [0]
        )
        #expect(series == fallback)
    }
}
