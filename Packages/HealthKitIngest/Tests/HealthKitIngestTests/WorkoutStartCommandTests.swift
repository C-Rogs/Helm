import CoachLLM
import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("WorkoutStartCommand")
struct WorkoutStartCommandTests {
    private let day = HelmDay(year: 2026, month: 7, day: 29)
    private let squatID = "exercise-squat"
    private let benchID = "exercise-bench"

    @Test("parses workout_start payload with exercises")
    func parsesPayloadWithExercises() {
        let text = """
        Ready when you are.
        {"schemaVersion":"workout_start.v1","helmDay":"2026-07-29","useAdjustedPrescription":true,"exercises":["Bench Press","Squat (Barbell)"]}
        """
        let payload = WorkoutStartPayloadParser.parse(from: text)
        #expect(payload?.schemaVersion == CoachOutputSchemaVersion.workoutStartV1.rawValue)
        #expect(payload?.helmDay == "2026-07-29")
        #expect(payload?.useAdjustedPrescription == true)
        #expect(payload?.exerciseLabels == ["Bench Press", "Squat (Barbell)"])
    }

    @Test("parses workout_start v2 with detailed sets")
    func parsesPayloadV2WithSets() throws {
        let text = """
        Starting now.
        {"schemaVersion":"workout_start.v2","helmDay":"2026-07-29","title":"Push","exercises":[{"name":"Bench Press","restSeconds":120,"sets":[{"setType":"warmup","reps":10,"massKg":60},{"setType":"normal","reps":8,"massKg":80,"rpe":8}]}]}
        """
        let payload = try #require(WorkoutStartPayloadParser.parse(from: text))
        #expect(payload.schemaVersion == CoachOutputSchemaVersion.workoutStartV2.rawValue)
        #expect(payload.hasDetailedSets)
        #expect(payload.exercises?.first?.sets?.count == 2)
        #expect(payload.exercises?.first?.sets?.first?.setType == "warmup")
    }

    @Test("parses workout_start when prose contains braces after JSON")
    func parsesPayloadWhenTrailingBracesExist() {
        let text = """
        Ready.
        {"schemaVersion":"workout_start.v1","helmDay":"2026-07-29","useAdjustedPrescription":false}
        Note: keep rest {short} between sets.
        """
        let payload = WorkoutStartPayloadParser.parse(from: text)
        #expect(payload?.schemaVersion == CoachOutputSchemaVersion.workoutStartV1.rawValue)
    }

    @Test("builds imported plan with warmup and working sets")
    func buildsImportedPlanFromV2Payload() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)

        let payload = WorkoutStartPayload(
            schemaVersion: CoachOutputSchemaVersion.workoutStartV2.rawValue,
            helmDay: "2026-07-29",
            title: "Push",
            exercises: [
                WorkoutStartExerciseSpec(
                    name: "Bench Press",
                    restSeconds: 120,
                    sets: [
                        WorkoutStartSetSpec(setType: "warmup", reps: 10, massKg: 60),
                        WorkoutStartSetSpec(setType: "drop_set", reps: 8, massKg: 80, rpe: 8)
                    ]
                )
            ]
        )

        let plan = try WorkoutStartPlanBuilder.importedPlan(from: payload, persistence: store)
        #expect(plan.exercises.count == 1)
        #expect(plan.exercises[0].exerciseID == benchID)
        #expect(plan.exercises[0].restDurationSeconds == 120)
        #expect(plan.exercises[0].sets.count == 2)
        #expect(plan.exercises[0].sets[0].setType == .warmup)
        #expect(plan.exercises[0].sets[0].mass?.kilograms == 60)
        #expect(plan.exercises[0].sets[1].setType == .dropSet)
        #expect(plan.exercises[0].sets[1].reps == 8)
    }

    @Test("reorders prescription when chat exercise list differs")
    func reordersPrescriptionFromExerciseList() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)

        let base = SessionPrescription(
            helmDay: day,
            title: "Push",
            exercises: [
                PrescribedExercise(exerciseID: benchID, order: 0, targetSets: 3, targetRepMin: 8, targetRepMax: 10),
                PrescribedExercise(exerciseID: squatID, order: 1, targetSets: 4, targetRepMin: 5, targetRepMax: 5)
            ]
        )

        let adjusted = try #require(
            try WorkoutStartPrescriptionResolver.prescription(
                exerciseLabels: ["Squat (Barbell)", "Bench Press"],
                base: base,
                persistence: store
            )
        )

        #expect(adjusted.exercises.map(\.exerciseID) == [squatID, benchID])
        #expect(adjusted.exercises[0].targetSets == 4)
        #expect(adjusted.exercises[1].targetSets == 3)
    }

    @Test("returns nil when exercise order already matches engine prescription")
    func returnsNilWhenOrderMatches() throws {
        let store = try PersistenceStore.inMemory()
        try seedExercises(in: store)

        let base = SessionPrescription(
            helmDay: day,
            exercises: [
                PrescribedExercise(exerciseID: benchID, order: 0, targetSets: 3),
                PrescribedExercise(exerciseID: squatID, order: 1, targetSets: 4)
            ]
        )

        let adjusted = try WorkoutStartPrescriptionResolver.prescription(
            exerciseLabels: ["Bench Press", "Squat (Barbell)"],
            base: base,
            persistence: store
        )
        #expect(adjusted == nil)
    }

    private func seedExercises(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: squatID,
            canonicalName: "squat (barbell)",
            displayName: "Squat (Barbell)",
            exerciseMode: .weightReps
        )
        try store.exercises.upsert(
            id: benchID,
            canonicalName: "bench press (barbell)",
            displayName: "Bench Press",
            exerciseMode: .weightReps
        )
    }
}
