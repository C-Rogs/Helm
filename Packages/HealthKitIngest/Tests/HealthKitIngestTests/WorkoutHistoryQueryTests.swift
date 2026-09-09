import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("WorkoutHistoryQuery")
struct WorkoutHistoryQueryTests {
    @Test("parses workout_query payload")
    func parsesQuery() {
        let text = """
        Checking.
        {"schemaVersion":"workout_query.v1","queryType":"latestCompleted"}
        """
        let payload = WorkoutQueryPayloadParser.parse(from: text)
        #expect(payload?.queryType == .latestCompleted)
    }

    @Test("latestCompleted formats session")
    func latestCompletedFormats() async throws {
        let store = try PersistenceStore.inMemory()
        let squatID = "exercise-squat"
        try store.exercises.upsert(
            id: squatID,
            canonicalName: "squat (barbell)",
            displayName: "Squat (Barbell)",
            exerciseMode: .weightReps
        )

        let completedAt = Calendar.current.date(from: DateComponents(
            timeZone: .current,
            year: 2026,
            month: 8,
            day: 3,
            hour: 17
        ))!
        try store.workoutSessions.insert(
            WorkoutSessionDraft(
                id: "session-pull",
                title: "Pull",
                startedAt: completedAt,
                endedAt: completedAt.addingTimeInterval(2_400),
                exercises: [
                    WorkoutSessionExerciseDraft(
                        id: "wse-1",
                        exerciseID: squatID,
                        displayOrder: 0,
                        exerciseMode: .weightReps,
                        sets: [
                            SetEntryDraft(
                                id: "set-1",
                                setIndex: 0,
                                mass: Mass(kilograms: 100),
                                reps: 5,
                                completedAt: completedAt
                            )
                        ]
                    )
                ]
            )
        )

        let service = WorkoutHistoryQueryService(store: store)
        let result = try service.run(WorkoutQueryPayload(queryType: .latestCompleted))
        #expect(result.contains("query=latestCompleted"))
        #expect(result.contains("Pull"))
        #expect(result.contains("Squat") || result.contains("100"))
    }

    @Test("native cardio formats duration and distance without strength volume")
    func nativeCardioFormats() throws {
        let store = try PersistenceStore.inMemory()
        let treadmillID = "exercise-treadmill"
        try store.exercises.upsert(
            id: treadmillID,
            canonicalName: "treadmill",
            displayName: "Treadmill",
            exerciseMode: .distanceDuration
        )
        let completedAt = Date(timeIntervalSince1970: 1_780_000_000)
        try store.workoutSessions.insert(
            WorkoutSessionDraft(
                id: "session-cardio",
                title: "Easy jog",
                startedAt: completedAt,
                endedAt: completedAt.addingTimeInterval(650),
                exercises: [
                    WorkoutSessionExerciseDraft(
                        exerciseID: treadmillID,
                        displayOrder: 0,
                        exerciseMode: .distanceDuration,
                        sets: [
                            SetEntryDraft(
                                setIndex: 0,
                                distanceKilometers: 2,
                                durationSeconds: 600,
                                rpe: 6,
                                completedAt: completedAt
                            )
                        ]
                    )
                ]
            )
        )

        let result = try WorkoutHistoryQueryService(store: store)
            .run(WorkoutQueryPayload(queryType: .latestCompleted))
        #expect(result.contains("source=native_cardio"))
        #expect(result.contains("logged_duration_s=600"))
        #expect(result.contains("distance_km=2.00"))
        #expect(result.contains("duration 10 min"))
        #expect(!result.contains("volume_kg="))
    }
}
