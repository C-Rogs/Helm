import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("HealthKit workout history persistence")
struct HealthKitWorkoutHistoryTests {

    @Test("shouldPersistToHistory excludes Helm phone and Watch bundles")
    func historyEligibility() {
        let phone = IngestSampleFilter.phoneBundleID
        let watch = IngestSampleFilter.watchBundleID

        #expect(IngestSampleFilter.shouldPersistToHistory(sourceBundleID: nil) == true)
        #expect(IngestSampleFilter.shouldPersistToHistory(sourceBundleID: phone) == false)
        #expect(IngestSampleFilter.shouldPersistToHistory(sourceBundleID: watch) == false)
        #expect(IngestSampleFilter.shouldPersistToHistory(sourceBundleID: "com.apple.health") == true)
        #expect(IngestSampleFilter.shouldPersistToHistory(sourceBundleID: "com.strava.stravaride") == true)
    }

    @Test("upsert inserts and updates healthKit workout")
    func upsertWorkout() async throws {
        let store = try PersistenceStore.inMemory()
        let startedAt = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!
        let endedAt = startedAt.addingTimeInterval(3_600)

        let sessionID = try store.workoutSessions.upsertHealthKitWorkout(
            hkUUID: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            title: "Football",
            startedAt: startedAt,
            endedAt: endedAt,
            activityType: "Football",
            activeEnergyKilocalories: 450,
            distanceMeters: 5_200,
            sourceBundleID: "com.apple.health"
        )

        #expect(sessionID.hasPrefix("hk_"))

        // Read back via summary
        let summaries = try store.workoutSessions.listSummaries(limit: 10)
        let match = try #require(summaries.first(where: { $0.id == sessionID }))

        #expect(match.source == .healthKit)
        #expect(match.title == "Football")
        #expect(match.hkActiveEnergyKilocalories == 450)
        #expect(match.hkTotalDistanceMeters == 5_200)
        #expect(match.totalVolumeKilograms == 0)
        #expect(match.totalSetCount == 0)
        #expect(match.exerciseCount == 0)
    }

    @Test("upsert updates existing healthKit workout by hk_uuid")
    func upsertUpdatesExisting() async throws {
        let store = try PersistenceStore.inMemory()
        let startedAt = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!
        let endedAt = startedAt.addingTimeInterval(3_600)
        let hkUUID = "B2C3D4E5-F6A7-8901-BCDE-F12345678901"

        let id1 = try store.workoutSessions.upsertHealthKitWorkout(
            hkUUID: hkUUID,
            title: "Running",
            startedAt: startedAt,
            endedAt: endedAt,
            activityType: "Running",
            activeEnergyKilocalories: 300,
            distanceMeters: 5_000,
            sourceBundleID: "com.apple.health"
        )

        let id2 = try store.workoutSessions.upsertHealthKitWorkout(
            hkUUID: hkUUID,
            title: "Running",
            startedAt: startedAt,
            endedAt: endedAt,
            activityType: "Running",
            activeEnergyKilocalories: 350,
            distanceMeters: 5_200,
            sourceBundleID: "com.apple.health"
        )

        #expect(id1 == id2)

        let summary = try store.workoutSessions.listSummaries(limit: 10)
            .first(where: { $0.id == id1 })
        #expect(summary?.hkActiveEnergyKilocalories == 350)
        #expect(summary?.hkTotalDistanceMeters == 5_200)
    }

    @Test("deleted healthKit workout is not resurrected by re-insert")
    func deletedNotResurrected() async throws {
        let store = try PersistenceStore.inMemory()
        let startedAt = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!
        let endedAt = startedAt.addingTimeInterval(3_600)
        let hkUUID = "C3D4E5F6-A7B8-9012-CDEF-123456789012"

        let id = try store.workoutSessions.upsertHealthKitWorkout(
            hkUUID: hkUUID,
            title: "Cycling",
            startedAt: startedAt,
            endedAt: endedAt,
            activityType: "Cycling",
            activeEnergyKilocalories: 200,
            distanceMeters: 10_000,
            sourceBundleID: "com.apple.health"
        )

        try store.workoutSessions.delete(id: id)

        // Re-insert same hkUUID. Should not resurrect the deleted row.
        let id2 = try store.workoutSessions.upsertHealthKitWorkout(
            hkUUID: hkUUID,
            title: "Cycling",
            startedAt: startedAt,
            endedAt: endedAt,
            activityType: "Cycling",
            activeEnergyKilocalories: 250,
            distanceMeters: 10_500,
            sourceBundleID: "com.apple.health"
        )

        // A new row was created because the old one was deleted
        #expect(id != id2)

        let active = try store.workoutSessions.listSummaries(limit: 10, scope: .active)
        #expect(active.contains(where: { $0.id == id2 }))
        #expect(!active.contains(where: { $0.id == id }))
    }

    @Test("prescription history excludes healthKit sessions")
    func prescriptionExcludesHealthKit() async throws {
        let store = try PersistenceStore.inMemory()
        let startedAt = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!

        // HealthKit session
        _ = try store.workoutSessions.upsertHealthKitWorkout(
            hkUUID: "D4E5F6A7-B8C9-0123-DEFG-123456789013",
            title: "Running",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            activityType: "Running",
            activeEnergyKilocalories: 200,
            distanceMeters: 5_000,
            sourceBundleID: "com.apple.health"
        )

        // Signal session
        try store.workoutSessions.insert(
            WorkoutSessionDraft(
                id: "signal-session-1",
                title: "Push",
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(2_400),
                exercises: [
                    WorkoutSessionExerciseDraft(
                        id: "wse-1",
                        exerciseID: "exercise-bench",
                        displayOrder: 0,
                        exerciseMode: .weightReps,
                        sets: [
                            SetEntryDraft(
                                id: "set-1",
                                setIndex: 0,
                                mass: Mass(kilograms: 80),
                                reps: 8,
                                completedAt: startedAt
                            )
                        ]
                    )
                ]
            )
        )

        let endDay = HelmDay(year: 2026, month: 8, day: 7)
        let history = try PrescriptionHistoryBuilder.history(
            from: store,
            endingAt: endDay
        )

        // Only the Signal session
        #expect(history.sessions.count == 1)
        #expect(history.sessions.first?.id.uuidString == "signal-session-1")
    }
}