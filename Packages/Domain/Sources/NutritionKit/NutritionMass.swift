import Foundation

enum NutritionMass {
    static let defaultBodyMassKg = 75.0
    static let minimumTDEEKcal = 1_200.0

    static func resolved(_ bodyMassKg: Double?, default defaultBodyMassKg: Double = defaultBodyMassKg) -> Double {
        guard let bodyMassKg, bodyMassKg.isFinite, bodyMassKg > 1 else {
            return defaultBodyMassKg
        }
        return bodyMassKg
    }

    static func flooredTDEE(_ estimate: Double, bodyMassKg: Double) -> Double {
        let mass = resolved(bodyMassKg)
        let seed = TDEECalculator.seedTDEE(bodyMassKg: mass)
        return max(estimate, seed * 0.5, minimumTDEEKcal)
    }
}
