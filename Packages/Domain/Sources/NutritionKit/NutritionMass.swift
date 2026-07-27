import Foundation

enum NutritionMass {
    static let defaultBodyMassKg = 75.0
    static let minimumTDEEKcal = 1_200.0
    static let stableWeightChangeThresholdKg = 0.1

    static func resolved(_ bodyMassKg: Double?, default defaultBodyMassKg: Double = defaultBodyMassKg) -> Double {
        guard let bodyMassKg, bodyMassKg.isFinite, bodyMassKg > 1 else {
            return defaultBodyMassKg
        }
        return bodyMassKg
    }

    static func flooredTDEE(_ estimate: Double, profileSeedTDEE: Double) -> Double {
        max(estimate, profileSeedTDEE * 0.5, minimumTDEEKcal)
    }

    /// Backward-compatible floor for legacy call sites without a profile seed.
    static func flooredTDEE(_ estimate: Double, bodyMassKg: Double) -> Double {
        let mass = resolved(bodyMassKg)
        let seed = TDEECalculator.seedTDEE(bodyMassKg: mass)
        return flooredTDEE(estimate, profileSeedTDEE: seed)
    }
}
