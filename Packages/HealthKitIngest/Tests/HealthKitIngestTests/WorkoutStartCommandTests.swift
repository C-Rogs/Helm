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
        #expect(payload?.exercises == ["Bench Press", "Squat (Barbell)"])
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
