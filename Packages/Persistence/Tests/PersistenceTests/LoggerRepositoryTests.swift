import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Logger repositories")
struct LoggerRepositoryTests {
    private let benchPressID = "exercise-bench-press"
    private let squatID = "exercise-squat"

    private func makeStore() throws -> PersistenceStore {
        try PersistenceStore.inMemory()
    }

    private func seedBenchPress(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press (barbell)",
            displayName: "Bench Press (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
        try store.exercises.addAlias(
            id: "alias-bench",
            exerciseID: benchPressID,
            alias: "Bench Press"
        )
    }

    private func seedSquat(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: squatID,
            canonicalName: "squat (barbell)",
            displayName: "Squat (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "quads"
        )
    }

    @Test("template round trip")
    func templateRoundTrip() throws {
        let store = try makeStore()
        try seedBenchPress(in: store)

        let draft = WorkoutTemplateDraft(
            id: "template-push",
            name: "Push Day",
            notes: "Chest focus",
            exercises: [
                WorkoutTemplateExerciseDraft(
                    exerciseID: benchPressID,
                    displayOrder: 0,
                    targetSetCount: 3,
                    targetRepMin: 8,
                    targetRepMax: 12,
                    targetMass: Mass(kilograms: 80)
                )
            ]
        )

        try store.workoutTemplates.insert(draft)
        let fetched = try store.workoutTemplates.fetch(id: draft.id)

        #expect(fetched?.name == "Push Day")
        #expect(fetched?.exercises.count == 1)
        #expect(fetched?.exercises[0].targetMass?.kilograms == 80)
    }

    @Test("personal record round trip")
    func personalRecordRoundTrip() throws {
        let store = try makeStore()
        try seedBenchPress(in: store)

        let achievedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let record = PersonalRecord(
            id: "pr-bench-e1rm",
            exerciseID: benchPressID,
            metricType: .bestEstimated1RM,
            metricValue: 120,
            achievedAt: achievedAt
        )

        try store.personalRecords.insert(record)
        let fetched = try store.personalRecords.fetchBest(
            exerciseID: benchPressID,
            metric: .bestEstimated1RM
        )

        #expect(fetched?.metricValue == 120)
        #expect(fetched?.metricType == .bestEstimated1RM)
    }

    @Test("previous performance picks matching set index from prior session")
    func previousPerformanceMatchesSetIndex() throws {
        let store = try makeStore()
        try seedBenchPress(in: store)

        let olderStart = Date(timeIntervalSince1970: 1_700_000_000)
        let olderSet1Completed = Date(timeIntervalSince1970: 1_700_000_100)
        let olderSet2Completed = Date(timeIntervalSince1970: 1_700_000_200)

        let olderSession = WorkoutSessionDraft(
            id: "session-older",
            startedAt: olderStart,
            endedAt: olderSet2Completed,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: benchPressID,
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            setIndex: 1,
                            mass: Mass(kilograms: 60),
                            reps: 10,
                            completedAt: olderSet1Completed
                        ),
                        SetEntryDraft(
                            setIndex: 2,
                            mass: Mass(kilograms: 80),
                            reps: 8,
                            completedAt: olderSet2Completed
                        )
                    ]
                )
            ]
        )
        try store.workoutSessions.insert(olderSession)

        let newerStart = Date(timeIntervalSince1970: 1_700_100_000)
        let newerSetCompleted = Date(timeIntervalSince1970: 1_700_100_100)
        let newerSession = WorkoutSessionDraft(
            id: "session-newer",
            startedAt: newerStart,
            endedAt: newerSetCompleted,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: benchPressID,
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            setIndex: 1,
                            mass: Mass(kilograms: 62.5),
                            reps: 10,
                            completedAt: newerSetCompleted
                        )
                    ]
                )
            ]
        )
        try store.workoutSessions.insert(newerSession)

        let previousSet2 = try store.workoutSessions.previousPerformance(
            exerciseID: benchPressID,
            setIndex: 2,
            excludingSessionID: newerSession.id
        )
        let previousSet1 = try store.workoutSessions.previousPerformance(
            exerciseID: benchPressID,
            setIndex: 1,
            excludingSessionID: newerSession.id
        )

        #expect(previousSet2?.mass?.kilograms == 80)
        #expect(previousSet2?.reps == 8)
        #expect(previousSet1?.mass?.kilograms == 60)
        #expect(previousSet1?.reps == 10)
    }

    @Test("previous performance ignores warmup bucket when asking for working set")
    func previousPerformanceRespectsWarmupBucket() throws {
        let store = try makeStore()
        try seedBenchPress(in: store)

        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSessionDraft(
            id: "session-warmup",
            startedAt: completedAt,
            endedAt: completedAt,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: benchPressID,
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            setIndex: 0,
                            setType: .warmup,
                            mass: Mass(kilograms: 40),
                            reps: 12,
                            completedAt: completedAt
                        ),
                        SetEntryDraft(
                            setIndex: 1,
                            setType: .normal,
                            mass: Mass(kilograms: 80),
                            reps: 8,
                            completedAt: completedAt.addingTimeInterval(60)
                        )
                    ]
                )
            ]
        )
        try store.workoutSessions.insert(session)

        let previous = try store.workoutSessions.previousPerformance(
            exerciseID: benchPressID,
            setIndex: 1,
            setType: .normal,
            excludingSessionID: "other-session"
        )

        #expect(previous?.mass?.kilograms == 80)
        #expect(previous?.setType == .normal)
    }

    @Test("estimated one rep max uses Epley across completed working sets")
    func estimatedOneRepMaxMatchesEpley() throws {
        let store = try makeStore()
        try seedSquat(in: store)

        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSessionDraft(
            id: "session-squat",
            startedAt: completedAt,
            endedAt: completedAt,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: squatID,
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            setIndex: 0,
                            setType: .warmup,
                            mass: Mass(kilograms: 60),
                            reps: 10,
                            completedAt: completedAt
                        ),
                        SetEntryDraft(
                            setIndex: 1,
                            mass: Mass(kilograms: 100),
                            reps: 10,
                            completedAt: completedAt.addingTimeInterval(60)
                        ),
                        SetEntryDraft(
                            setIndex: 2,
                            mass: Mass(kilograms: 120),
                            reps: 5,
                            completedAt: completedAt.addingTimeInterval(120)
                        )
                    ]
                )
            ]
        )
        try store.workoutSessions.insert(session)

        let estimated = try store.workoutSessions.estimatedOneRM(exerciseID: squatID)
        let expectedFrom120x5 = Mass(kilograms: 120) // Epley: 120 * (1 + 5/30) = 140
        let handComputed = Mass(kilograms: 120 * (1.0 + 5.0 / 30.0))

        #expect(estimated != nil)
        #expect(abs((estimated?.kilograms ?? 0) - handComputed.kilograms) < 0.01)
        #expect((estimated?.kilograms ?? 0) > Mass(kilograms: 100 * (1.0 + 10.0 / 30.0)).kilograms)
        _ = expectedFrom120x5
    }

    @Test("exercise alias resolves canonical exercise id")
    func exerciseAliasResolution() throws {
        let store = try makeStore()
        try seedBenchPress(in: store)

        let resolved = try store.exercises.resolveExerciseID(normalizedAlias: "bench press")
        #expect(resolved == benchPressID)
    }
}
