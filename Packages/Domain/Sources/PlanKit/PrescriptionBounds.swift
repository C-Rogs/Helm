import Core
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

    public static func isLoadWithinBounds(
        currentKg: Double,
        proposedKg: Double,
        intent: LoadAdjustmentIntent = .coachSuggested,
        enforceCoachLoadCaps: Bool = true
    ) -> Bool {
        guard proposedKg >= 0 else { return false }

        switch intent {
        case .userDirected:
            return true
        case .coachSuggested:
            if !enforceCoachLoadCaps {
                return true
            }
            if proposedKg > currentKg {
                let maxIncrease = maxLoadDelta(for: currentKg)
                return proposedKg <= currentKg + maxIncrease
            }
            return true
        }
    }

    public static func clampedLoadKg(_ proposedKg: Double) -> Double {
        max(0, proposedKg)
    }
}
