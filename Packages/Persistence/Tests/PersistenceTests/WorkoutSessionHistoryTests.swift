import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Workout session history")
struct WorkoutSessionHistoryTests {
    private let squatID = "exercise-squat"

    @Test("lists, fetches, and updates completed sessions")
    func historyRoundTrip() throws {
        let store = try PersistenceStore.inMemory()
        try store.exercises.upsert(
            id: squatID,
            canonicalName: "squat (barbell)",
            displayName: "Squat (Barbell)",
            exerciseMode: .weightReps
        )

        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSessionDraft(
            id: "session-history",
            title: "Leg Day",
            startedAt: completedAt,
            endedAt: completedAt,
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
        try store.workoutSessions.insert(session)

        let summaries = try store.workoutSessions.listSummaries(limit: 10)
        #expect(summaries.count == 1)
        #expect(summaries[0].title == "Leg Day")

        let fetched = try #require(try store.workoutSessions.fetch(id: session.id))
        #expect(fetched.exercises[0].sets[0].mass?.kilograms == 100)

        let updated = WorkoutSessionDraft(
            id: session.id,
            title: "Leg Day (edited)",
            startedAt: session.startedAt,
            endedAt: session.endedAt,
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
                            mass: Mass(kilograms: 105),
                            reps: 5,
                            completedAt: completedAt
                        )
                    ]
                )
            ]
        )
        try store.workoutSessions.updateCompletedSession(updated)

        let refetched = try #require(try store.workoutSessions.fetch(id: session.id))
        #expect(refetched.title == "Leg Day (edited)")
        #expect(refetched.exercises[0].sets[0].mass?.kilograms == 105)
    }

    @Test("starts active session from template with prefilled sets")
    func templateStartPrefill() throws {
        let store = try PersistenceStore.inMemory()
        try store.exercises.upsert(
            id: squatID,
            canonicalName: "squat (barbell)",
            displayName: "Squat (Barbell)",
            exerciseMode: .weightReps
        )

        let template = WorkoutTemplateDraft(
            id: "template-legs",
            name: "Legs",
            exercises: [
                WorkoutTemplateExerciseDraft(
                    exerciseID: squatID,
                    displayOrder: 0,
                    targetSetCount: 2,
                    targetRepMin: 5,
                    targetMass: Mass(kilograms: 120)
                )
            ]
        )
        try store.workoutTemplates.insert(template)

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try store.activeSessions.startSessionFromTemplate(template: template, startedAt: startedAt)
        let snapshot = try #require(try store.activeSessions.fetchActiveSnapshot(at: startedAt))

        #expect(snapshot.session.source == .template)
        #expect(snapshot.session.exercises.count == 1)
        #expect(snapshot.session.exercises[0].sets.count == 2)
        #expect(snapshot.session.exercises[0].sets[0].mass?.kilograms == 120)
        #expect(snapshot.session.exercises[0].sets[0].reps == 5)
    }
}
