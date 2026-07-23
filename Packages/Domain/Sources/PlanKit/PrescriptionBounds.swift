import Foundation

/// Safe bounds for prescription targets and in-session adjustments.
public enum PrescriptionBounds {
    public static let minSetsPerExercise = 1
    public static let maxSetsPerExercise = 6
    public static let minRPE = 5.0
    public static let maxRPE = 10.0

    public static func clampSets(_ sets: Int) -> Int {
        min(maxSetsPerExercise, max(minSetsPerExercise, sets))
    }

    public static func clampRPE(_ rpe: Double, cap: Double) -> Double {
        min(cap, maxRPE, max(minRPE, rpe))
    }
}
