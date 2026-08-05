import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Training history export")
struct TrainingHistoryExportTests {
    private let benchPressID = "ex-bench"
    private let customID = "ex-custom-fly"

    @Test("round-trips completed sessions, custom exercises, and aliases")
    func roundTrip() throws {
        let source = try PersistenceStore.inMemory()
        try seed(in: source)

        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = WorkoutSessionDraft(
            id: "session-1",
            title: "Push",
            startedAt: started,
            endedAt: started.addingTimeInterval(3600),
            status: .completed,
            source: .manual,
            exercises: [
                WorkoutSessionExerciseDraft(
                    id: "wse-1",
                    exerciseID: benchPressID,
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            id: "set-1",
                            setIndex: 1,
                            setType: .normal,
                            status: .completed,
                            mass: Mass(kilograms: 100),
                            reps: 5,
                            rpe: 8,
                            completedAt: started
                        )
                    ]
                ),
                WorkoutSessionExerciseDraft(
                    id: "wse-2",
                    exerciseID: customID,
                    displayOrder: 1,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            id: "set-2",
                            setIndex: 1,
                            setType: .normal,
                            status: .completed,
                            mass: Mass(kilograms: 20),
                            reps: 12,
                            completedAt: started
                        )
                    ]
                )
            ]
        )
        try source.workoutSessions.insert(draft)

        let exporter = TrainingHistoryExportService(
            sessions: source.workoutSessions,
            exercises: source.exercises
        )
        let payload = try exporter.exportHistory(
            lookbackDays: 90,
            now: started.addingTimeInterval(86_400)
        )
        #expect(payload.sessions.count == 1)
        #expect(payload.customExercises.count == 1)
        #expect(payload.aliases.contains { $0.alias == "Bench Press" })

        let data = try exporter.encode(payload)
        let decoded = try exporter.decode(data)

        let destination = try PersistenceStore.inMemory()
        try destination.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press barbell",
            displayName: "Bench Press (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )

        let importer = TrainingHistoryExportService(
            sessions: destination.workoutSessions,
            exercises: destination.exercises
        )
        let result = try importer.importHistory(decoded)
        #expect(result.importedSessionCount == 1)
        #expect(result.importedSetCount == 2)
        #expect(result.upsertedCustomExerciseCount == 1)

        let fetched = try destination.workoutSessions.fetch(id: "session-1")
        #expect(fetched?.exercises.count == 2)
        #expect(fetched?.exercises[0].sets[0].mass?.kilograms == 100)
        #expect(try destination.exercises.fetchSummary(id: customID)?.isCustom == true)
        #expect(try destination.exercises.resolveImportedTitle("Bench Press")?.exerciseID == benchPressID)

        let again = try importer.importHistory(decoded)
        #expect(again.importedSessionCount == 0)
        #expect(again.skippedDuplicateCount == 1)
    }

    @Test("export clips to lookback window")
    func lookbackClip() throws {
        let store = try PersistenceStore.inMemory()
        try seed(in: store)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = WorkoutSessionDraft(
            id: "recent",
            title: "Recent",
            startedAt: now.addingTimeInterval(-10 * 86_400),
            endedAt: now.addingTimeInterval(-10 * 86_400 + 3600),
            status: .completed,
            source: .manual,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: benchPressID,
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            setIndex: 1,
                            status: .completed,
                            mass: Mass(kilograms: 80),
                            reps: 8,
                            completedAt: now.addingTimeInterval(-10 * 86_400)
                        )
                    ]
                )
            ]
        )
        let old = WorkoutSessionDraft(
            id: "old",
            title: "Old",
            startedAt: now.addingTimeInterval(-120 * 86_400),
            endedAt: now.addingTimeInterval(-120 * 86_400 + 3600),
            status: .completed,
            source: .manual,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: benchPressID,
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(
                            setIndex: 1,
                            status: .completed,
                            mass: Mass(kilograms: 70),
                            reps: 8,
                            completedAt: now.addingTimeInterval(-120 * 86_400)
                        )
                    ]
                )
            ]
        )
        try store.workoutSessions.insert(recent)
        try store.workoutSessions.insert(old)

        let export = try TrainingHistoryExportService(
            sessions: store.workoutSessions,
            exercises: store.exercises
        ).exportHistory(lookbackDays: 90, now: now)

        #expect(export.sessions.map(\.id) == ["recent"])
    }

    private func seed(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press barbell",
            displayName: "Bench Press (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
        try store.exercises.upsert(
            id: customID,
            canonicalName: "machine fly custom",
            displayName: "Machine Fly Custom",
            exerciseMode: .weightReps,
            isCustom: true,
            primaryMuscleGroup: "chest"
        )
        try store.exercises.addAlias(id: "alias-bench", exerciseID: benchPressID, alias: "Bench Press")
    }
}
