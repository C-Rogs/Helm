import Foundation
import Testing
@testable import HealthKitIngest

@Suite("Workout HealthKit writer")
struct WorkoutHealthKitWriterTests {
    @Test("own-bundle workouts are filtered from ingest")
    func ownWritesFiltered() async throws {
        let mock = MockHealthKitStoreClient()
        let writer = WorkoutHealthKitWriter(store: mock)

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3_600)
        let saved = try await writer.saveWorkout(
            WorkoutWriteRequest(sessionID: "session-1", startedAt: start, endedAt: end, title: "Push")
        )

        #expect(mock.lastSavedEnergyKilocalories != nil)
        #expect(mock.lastSavedEnergyKilocalories! > 0)
        #expect(
            WorkoutHealthKitWriter.shouldReIngest(
                savedWorkout: saved,
                ownBundleID: HealthKitIngest.defaultOwnBundleID
            ) == false
        )
        #expect(IngestSampleFilter.shouldIngest(sourceBundleID: saved.sourceBundleID, ownBundleID: HealthKitIngest.defaultOwnBundleID) == false)
    }
}
