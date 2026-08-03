import Core
import Foundation

/// Soft advisory when logged RIR/RPE disagrees with historical Epley e1RM.
public enum RIRConsistencyFlag: Sendable, Equatable {
    /// Claimed reps-to-failure exceeds what historical best e1RM predicts at this load.
    case overstatedSpareCapacity

    public var message: String {
        switch self {
        case .overstatedSpareCapacity:
            return "RIR looks high vs your e1RM history"
        }
    }
}

enum RIRConsistency {
    /// Standard proximity conversion used when the logger captures RPE only.
    static func rirFromRPE(_ rpe: Double) -> Double {
        max(0, min(10, 10 - rpe))
    }

    /// Predicted reps to failure at `mass` from historical best e1RM (Epley inverse).
    static func predictedRepsToFailure(mass: Mass, historicalBestE1RM: Mass) -> Double {
        guard mass.kilograms > 0, historicalBestE1RM.kilograms > 0 else { return 0 }
        return max(0, 30.0 * (historicalBestE1RM.kilograms / mass.kilograms - 1.0))
    }

    /// Returns a flag when claimed capacity (reps + RIR) is well above history.
    /// `spareRepMargin` absorbs normal RIR misestimation (~1-2 reps).
    static func evaluate(
        mass: Mass,
        reps: Int,
        claimedRIR: Double,
        historicalBestE1RM: Mass?,
        spareRepMargin: Double = 2.0
    ) -> RIRConsistencyFlag? {
        guard
            reps > 0,
            mass.kilograms > 0,
            claimedRIR >= 0,
            let history = historicalBestE1RM,
            history.kilograms > 0
        else {
            return nil
        }

        let predicted = predictedRepsToFailure(mass: mass, historicalBestE1RM: history)
        let claimed = Double(reps) + claimedRIR
        if claimed > predicted + spareRepMargin {
            return .overstatedSpareCapacity
        }
        return nil
    }
}
