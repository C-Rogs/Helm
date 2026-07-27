import Foundation

/// Safe bounds for prescription targets and in-session adjustments.
public enum PrescriptionBounds {
    public static let minSetsPerExercise = 1
    public static let maxSetsPerExercise = 6
    public static let minRPE = 5.0
    public static let maxRPE = 10.0
    public static let maxLoadAdjustmentFraction = 0.10
    public static let minLoadAdjustmentKg = 2.5

    public static func clampSets(_ sets: Int) -> Int {
        min(maxSetsPerExercise, max(minSetsPerExercise, sets))
    }

    public static func clampRPE(_ rpe: Double, cap: Double = maxRPE) -> Double {
        min(cap, maxRPE, max(minRPE, rpe))
    }

    public static func maxLoadDelta(for currentKg: Double) -> Double {
        max(currentKg * maxLoadAdjustmentFraction, minLoadAdjustmentKg)
    }

    public static func isLoadWithinBounds(currentKg: Double, proposedKg: Double) -> Bool {
        let delta = maxLoadDelta(for: currentKg)
        return proposedKg >= currentKg - delta && proposedKg <= currentKg + delta
    }
}
