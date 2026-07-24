import Core
import Foundation

public struct NutritionTargetContext: Sendable, Hashable, Equatable {
    public let bodyMassKg: Double?
    public let dayType: NutritionDayType
    public let loggedDay: NutritionDay?

    public init(bodyMassKg: Double? = nil, dayType: NutritionDayType, loggedDay: NutritionDay? = nil) {
        self.bodyMassKg = bodyMassKg
        self.dayType = dayType
        self.loggedDay = loggedDay
    }
}

enum MacroTargetCalculator {
    static let proteinGramsPerKg = 2.0

    static func phaseCalorieAdjustment(for phase: PhaseGoal) -> Double {
        let kcalPerDayPerKgWeek = TDEECalculator.kcalPerKgBodyMassChange / 7.0
        switch phase.phase {
        case .cut:
            let rate = min(phase.weeklyRateKg ?? 0.5, 1.0)
            return rate * kcalPerDayPerKgWeek
        case .gain:
            let rate = min(phase.weeklyRateKg ?? 0.25, 1.0)
            return -rate * kcalPerDayPerKgWeek
        case .maintain:
            return 0
        }
    }

    static func resolvedTDEE(trend: NutritionTrendState, bodyMassKg: Double) -> Double {
        let mass = NutritionMass.resolved(bodyMassKg)
        let seed = TDEECalculator.seedTDEE(bodyMassKg: mass)
        let raw = trend.estimatedTDEEKcal ?? seed
        let floored = NutritionMass.flooredTDEE(raw, bodyMassKg: mass)
        return floored.isFinite ? floored : seed
    }

    static func carbShare(for dayType: NutritionDayType) -> Double {
        switch dayType {
        case .training:
            0.45
        case .rest, .deload:
            0.35
        }
    }

    static func compute(
        context: NutritionTargetContext,
        phase: PhaseGoal,
        trend: NutritionTrendState
    ) -> MacroTargets {
        let mass = NutritionMass.resolved(context.bodyMassKg)
        let tdee = resolvedTDEE(trend: trend, bodyMassKg: mass)
        let proteinGrams = Int((mass * proteinGramsPerKg).rounded())
        let proteinKcal = proteinGrams * 4
        let targetCalories = max(
            Int((tdee - phaseCalorieAdjustment(for: phase)).rounded()),
            proteinKcal,
            Int(NutritionMass.minimumTDEEKcal.rounded())
        )

        let remainingKcal = max(targetCalories - proteinKcal, 0)

        let carbShare = carbShare(for: context.dayType)
        let carbKcal = Int((Double(remainingKcal) * carbShare).rounded())
        let fatKcal = max(remainingKcal - carbKcal, 0)

        return MacroTargets(
            caloriesKcal: targetCalories,
            proteinGrams: proteinGrams,
            carbohydrateGrams: carbKcal / 4,
            fatGrams: fatKcal / 9,
            dayType: context.dayType,
            estimatedTDEEKcal: Int(tdee.rounded()),
            macroGapKilocalories: context.loggedDay.flatMap(MacroGapCalculator.macroGap(for:))
        )
    }
}
