import Core
import Foundation
import Testing

struct ActiveSessionRecoveryPolicyTests {
    @Test("abandons untouched prescription shell")
    func abandonsUntouchedPrescription() {
        let snapshot = snapshot(
            source: .prescription,
            sets: [
                SetEntryDraft(setIndex: 0, status: .planned),
                SetEntryDraft(setIndex: 1, status: .planned),
            ]
        )

        #expect(ActiveSessionRecoveryPolicy.shouldAbandonUntouchedPrescription(snapshot))
    }

    @Test("keeps prescription session with completed work")
    func keepsPrescriptionWithWork() {
        let snapshot = snapshot(
            source: .prescription,
            sets: [
                SetEntryDraft(setIndex: 0, status: .completed, reps: 8),
                SetEntryDraft(setIndex: 1, status: .planned),
            ]
        )

        #expect(!ActiveSessionRecoveryPolicy.shouldAbandonUntouchedPrescription(snapshot))
    }

    @Test("keeps manual session even when untouched")
    func keepsManualSession() {
        let snapshot = snapshot(
            source: .manual,
            sets: [SetEntryDraft(setIndex: 0, status: .planned)]
        )

        #expect(!ActiveSessionRecoveryPolicy.shouldAbandonUntouchedPrescription(snapshot))
    }

    @Test("keeps prescription session after rest timer use")
    func keepsPrescriptionAfterRestTimer() {
        let snapshot = ActiveSessionSnapshot(
            session: sessionDraft(
                source: .prescription,
                sets: [SetEntryDraft(setIndex: 0, status: .planned)]
            ),
            recoveryState: .active,
            restTimer: RestTimer(id: "timer", phase: .running, endsAt: .now.addingTimeInterval(90))
        )

        #expect(!ActiveSessionRecoveryPolicy.shouldAbandonUntouchedPrescription(snapshot))
    }

    private func snapshot(source: WorkoutSessionSource, sets: [SetEntryDraft]) -> ActiveSessionSnapshot {
        ActiveSessionSnapshot(
            session: sessionDraft(source: source, sets: sets),
            recoveryState: .active
        )
    }

    private func sessionDraft(source: WorkoutSessionSource, sets: [SetEntryDraft]) -> WorkoutSessionDraft {
        WorkoutSessionDraft(
            startedAt: .now,
            status: .active,
            source: source,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: "bench",
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: sets
                ),
            ]
        )
    }
}
