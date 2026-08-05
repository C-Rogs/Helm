import Core
import Foundation

public enum ActiveSessionPrescriptionBridge {
    public static func prescribedSession(from snapshot: ActiveSessionSnapshot) -> SessionPrescription {
        let helmDay = HelmDay.day(for: snapshot.session.startedAt, calendar: .current)
        let exercises = snapshot.session.exercises
            .sorted { $0.displayOrder < $1.displayOrder }
            .enumerated()
            .map { index, exercise in
                let working = exercise.sets.filter { !$0.setType.isWarmup }
                let warmups = exercise.sets.filter { $0.setType.isWarmup }
                let templateSet = working.first(where: { $0.status == .planned })
                    ?? working.first
                    ?? exercise.sets.first(where: { $0.status == .planned })
                    ?? exercise.sets.first
                return PrescribedExercise(
                    exerciseID: exercise.exerciseID,
                    order: index,
                    targetSets: max(working.count, 1),
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
