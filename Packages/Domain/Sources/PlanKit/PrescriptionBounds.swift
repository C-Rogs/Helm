import Core
import Foundation

/// Planning bounds used when the engine generates a prescription.
///
/// These shape engine-authored volume and intensity only. In-session coach
/// adjustments are not gated by them: the athlete's request wins.
public enum PrescriptionBounds {
    public static let minSetsPerExercise = 1
    public static let maxSetsPerExercise = 4
    public static let minRPE = 5.0
    public static let maxRPE = 10.0

    public static func clampSets(_ sets: Int) -> Int {
        min(maxSetsPerExercise, max(minSetsPerExercise, sets))
    }

    public static func clampRPE(_ rpe: Double, cap: Double = maxRPE) -> Double {
        min(cap, maxRPE, max(minRPE, rpe))
    }

    public static func clampedLoadKg(_ proposedKg: Double) -> Double {
        max(0, proposedKg)
    }
}
