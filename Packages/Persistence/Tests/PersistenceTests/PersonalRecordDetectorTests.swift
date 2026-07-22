import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Personal record detector")
struct PersonalRecordDetectorTests {
    private let benchPressID = "exercise-bench-press"

    @Test("detects weight and e1RM improvements from queries")
    func detectsImprovements() throws {
        let store = try PersistenceStore.inMemory()
        try store.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press (barbell)",
            displayName: "Bench Press (Barbell)",
            exerciseMode: .weightReps
        )

        let priorCompleted = Date(timeIntervalSince1970: 1_700_000_000)
        try store.workoutSessions.insert(
            WorkoutSessionDraft(
                id: "session-old",
                startedAt: priorCompleted,
                endedAt: priorCompleted,
                exercises: [
                    WorkoutSessionExerciseDraft(
                        exerciseID: benchPressID,
                        displayOrder: 0,
                        exerciseMode: .weightReps,
                        sets: [
                            SetEntryDraft(
                                setIndex: 0,
                                mass: Mass(kilograms: 80),
                                reps: 8,
                                completedAt: priorCompleted
                            )
                        ]
                    )
                ]
            )
        )

        let newCompleted = Date(timeIntervalSince1970: 1_700_100_000)
        let newSession = WorkoutSessionDraft(
            id: "session-new",
            startedAt: newCompleted,
            endedAt: newCompleted,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: benchPressID,
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            id: "set-new",
                            setIndex: 0,
                            mass: Mass(kilograms: 90),
                            reps: 5,
                            completedAt: newCompleted
                        )
                    ]
                )
            ]
        )

        let records = try PersonalRecordDetector.detect(in: newSession, repository: store.workoutSessions)

        #expect(records.contains { $0.metricType == .maxWeight && $0.metricValue == 90 })
        #expect(records.contains { $0.metricType == .bestEstimated1RM })
    }
}
