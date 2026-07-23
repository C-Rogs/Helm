import Foundation

enum TDEECalculator {
    static let kcalPerKgBodyMassChange = 7_700.0
    static let defaultMaintenanceKcalPerKg = 33.0
    static let blendPriorWeight = 0.5

    static func impliedTDEE(averageIntakeKcal: Double, weightChangeKg: Double) -> Double {
        averageIntakeKcal - (weightChangeKg * kcalPerKgBodyMassChange / 7.0)
    }

    static func seedTDEE(bodyMassKg: Double) -> Double {
        bodyMassKg * defaultMaintenanceKcalPerKg
    }

    static func blendedEstimate(prior: Double, implied: Double) -> Double {
        prior * blendPriorWeight + implied * (1 - blendPriorWeight)
    }
}
