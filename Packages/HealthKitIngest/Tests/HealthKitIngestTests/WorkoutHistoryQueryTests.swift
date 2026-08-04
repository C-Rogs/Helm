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
}
