import Core
import Foundation
import HealthKit
import Testing
@testable import HealthKitIngest
@testable import Persistence

@Suite("Workout TRIMP ingest")
struct WorkoutTRIMPIngestTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    @Test("observed workout updates next-day prior-day TRIMP")
    func workoutUpdatesNextDayTRIMP() async throws {
        let store = try PersistenceStore.inMemory()
        let mockStore = MockHealthKitStoreClient()
        let writer = IngestPersistenceWriter(store: store, calendar: calendar)

        let workoutDay = HelmDay(year: 2026, month: 7, day: 21)
        let nextDay = workoutDay.adding(days: 1, calendar: calendar)
        let workoutStart = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 18))
        )
        let workoutEnd = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 19))
        )

        try store.dailyMetrics.upsert(
            DailyMetrics(helmDay: workoutDay, restingHeartRate: 55)
        )

        let workout = IngestWorkoutSample(
            id: UUID(),
            start: workoutStart,
            end: workoutEnd,
            sourceBundleID: "com.cameronro.helm.watchkitapp"
        )

        let heartRateType = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let heartRates: [Double] = [120, 130, 140, 150, 145, 135]
        let hrSamples = heartRates.enumerated().map { index, bpm in
            let start = workoutStart.addingTimeInterval(Double(index * 600))
            let end = start.addingTimeInterval(60)
            return HKQuantitySample(
                type: heartRateType,
                quantity: HKQuantity(unit: unit, doubleValue: bpm),
                start: start,
                end: end
            )
        }
        mockStore.setSampleResults(hrSamples, for: heartRateType)

        let ingester = WorkoutTRIMPIngester(
            store: mockStore,
            persistence: store,
            calendar: calendar
        )
        let trimpByTargetDay = try await ingester.trimpByTargetDay(for: [workout])

        let delta = IngestDelta(
            kind: .workout,
            addedWorkouts: [workout],
            trimpByTargetDay: trimpByTargetDay
        )
        let families = try writer.apply(delta: delta)

        let nextDayMetrics = try store.dailyMetrics.fetch(helmDay: nextDay)

        #expect(families.contains(.workouts))
        #expect(trimpByTargetDay[nextDay] != nil)
        #expect(nextDayMetrics?.priorDayTRIMP ?? 0 > 0)
    }

    @Test("Edwards TRIMP calculator assigns load to the following logical day")
    func calculatorTargetDay() {
        let workoutStart = Date(timeIntervalSince1970: 1_700_000_000)
        let workoutEnd = workoutStart.addingTimeInterval(3_600)
        let workout = IngestWorkoutSample(
            id: UUID(),
            start: workoutStart,
            end: workoutEnd,
            sourceBundleID: "watch"
        )
        let readings: [(date: Date, bpm: Double)] = (0..<3).map { index in
            (workoutStart.addingTimeInterval(Double(index) * 1_200), 140)
        }

        let result = WorkoutTRIMPCalculator.trimp(
            for: workout,
            heartRateReadings: readings,
            restingHeartRate: 55,
            athleteAgeYears: nil,
            calendar: calendar
        )

        #expect(result != nil)
        #expect(result?.targetDay == result?.workoutDay.adding(days: 1, calendar: calendar))
        #expect(result?.trimp ?? 0 > 0)
    }
}
