import Foundation

/// Hevy-style bodyweight tonnage rules for set volume.
public enum BodyweightVolume {
    /// Full bodyweight catalog moves count athlete BW toward volume (pull-up, dip, push-up).
    public static func usesFullBodyweight(exerciseMode: ExerciseMode) -> Bool {
        exerciseMode == .bodyweightReps
    }

    /// Per-set volume mass (kg × reps) from logged column value and athlete BW snapshot.
    ///
    /// - Full-BW catalog moves: column stores added kg only; volume uses BW + added.
    /// - Other modes: column stores load; volume uses column value only.
    public static func effectiveMassKg(
        loggedMassKg: Double?,
        exerciseMode: ExerciseMode,
        bodyweightKg: Double?
    ) -> Double {
        let added = max(0, loggedMassKg ?? 0)
        guard usesFullBodyweight(exerciseMode: exerciseMode) else {
            return added
        }
        let bodyweight = max(0, bodyweightKg ?? 0)
        return bodyweight + added
    }

    public static func setVolumeKg(
        loggedMassKg: Double?,
        reps: Int,
        exerciseMode: ExerciseMode,
        bodyweightKg: Double?
    ) -> Double {
        let mass = effectiveMassKg(
            loggedMassKg: loggedMassKg,
            exerciseMode: exerciseMode,
            bodyweightKg: bodyweightKg
        )
        return mass * Double(max(reps, 0))
    }
}
