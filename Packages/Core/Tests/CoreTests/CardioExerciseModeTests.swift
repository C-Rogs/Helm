import Foundation
import Testing
@testable import Core

@Suite("Cardio exercise modes")
struct CardioExerciseModeTests {
    @Test("cardio defaults to one interval")
    func defaultIntervalCount() {
        #expect(ExerciseMode.duration.defaultIntervalCount == 1)
        #expect(ExerciseMode.distanceDuration.defaultIntervalCount == 1)
        #expect(ExerciseMode.weightReps.defaultIntervalCount == 3)
    }

    @Test("completion validation follows exercise mode")
    func completionValidation() {
        #expect(
            ExerciseMode.duration.completionValidationMessage(
                for: SetEntryDraft(setIndex: 0, durationSeconds: 600)
            ) == nil
        )
        #expect(
            ExerciseMode.distanceDuration.completionValidationMessage(
                for: SetEntryDraft(setIndex: 0, durationSeconds: 600)
            ) != nil
        )
        #expect(
            ExerciseMode.distanceDuration.completionValidationMessage(
                for: SetEntryDraft(
                    setIndex: 0,
                    distanceKilometers: 2,
                    durationSeconds: 600
                )
            ) == nil
        )
        #expect(
            ExerciseMode.bodyweightReps.completionValidationMessage(
                for: SetEntryDraft(setIndex: 0, reps: 10)
            ) == nil
        )
    }

    @Test("native cardio summary classification requires all exercises")
    func nativeCardioSummary() {
        let cardio = WorkoutSessionSummary(
            id: "cardio",
            startedAt: Date(),
            totalVolumeKilograms: 0,
            totalSetCount: 1,
            totalRepCount: 0,
            exerciseCount: 1,
            cardioExerciseCount: 1,
            loggedDurationSeconds: 600,
            loggedDistanceKilometers: 2
        )
        let mixed = WorkoutSessionSummary(
            id: "mixed",
            startedAt: Date(),
            totalVolumeKilograms: 100,
            totalSetCount: 2,
            totalRepCount: 5,
            exerciseCount: 2,
            cardioExerciseCount: 1
        )
        #expect(cardio.isNativeCardio)
        #expect(!mixed.isNativeCardio)
    }
}
