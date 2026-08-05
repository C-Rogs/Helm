import Core
import Foundation

public enum ActiveSessionPrescriptionBridge {
    public static func prescribedSession(from snapshot: ActiveSessionSnapshot) -> SessionPrescription {
        let helmDay = HelmDay.day(for: snapshot.session.startedAt, calendar: .current)
        let exercises = snapshot.session.exercises
            .sorted { $0.displayOrder < $1.displayOrder }
            .enumerated()
            .map { index, exercise in
                let prescribedWorking = exercise.sets.filter { $0.setType.countsAsPrescribedWorkingSet }
                let warmups = exercise.sets.filter { $0.setType.isWarmup }
                let templateSet = prescribedWorking.first(where: { $0.status == .planned })
                    ?? prescribedWorking.first
                    ?? exercise.sets.first(where: { $0.status == .planned && !$0.setType.isWarmup })
                    ?? exercise.sets.first
                // Drop / assisted rows are not working slots. Floor at 1 only when the
                // exercise has no prescribed-working rows yet (empty or warmups/drops only).
                let targetSets = prescribedWorking.isEmpty ? 1 : prescribedWorking.count
                return PrescribedExercise(
                    exerciseID: exercise.exerciseID,
                    order: index,
                    targetSets: targetSets,
                    warmupSets: warmups.count,
                    targetRepMin: templateSet?.reps,
                    targetRepMax: templateSet?.reps,
                    targetMass: templateSet?.mass,
                    targetRPE: templateSet?.rpe
                )
            }

        return SessionPrescription(helmDay: helmDay, exercises: exercises)
    }
}
