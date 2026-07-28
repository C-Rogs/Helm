import Core
import Foundation

public enum PrescriptionCoachSnapshotBuilder {
    public static let preStartSessionID = "pre-start-prescription"

    public static func snapshot(
        from prescription: SessionPrescription,
        title: String? = nil
    ) -> ActiveSessionSnapshot {
        let startedAt = Date()
        let exercises = prescription.exercises.sorted { $0.order < $1.order }.enumerated().map { index, exercise in
            let setCount = max(exercise.targetSets, 1)
            let reps = exercise.targetRepMin ?? exercise.targetRepMax
            let sets = (0 ..< setCount).map { setIndex in
                SetEntryDraft(
                    id: "\(exercise.exerciseID)-\(setIndex)",
                    setIndex: setIndex,
                    setType: .normal,
                    status: .planned,
                    mass: exercise.targetMass,
                    reps: reps,
                    rpe: exercise.targetRPE
                )
            }
            return WorkoutSessionExerciseDraft(
                id: exercise.exerciseID,
                exerciseID: exercise.exerciseID,
                displayOrder: index,
                exerciseMode: .weightReps,
                targetRestSeconds: 90,
                sets: sets
            )
        }

        let session = WorkoutSessionDraft(
            id: preStartSessionID,
            title: title ?? prescription.title,
            startedAt: startedAt,
            status: .active,
            source: .prescription,
            exercises: exercises
        )

        return ActiveSessionSnapshot(
            session: session,
            recoveryState: .active
        )
    }
}
