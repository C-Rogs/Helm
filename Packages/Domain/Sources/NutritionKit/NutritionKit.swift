import Core
import Foundation

/// Adaptive TDEE and macro targets (pure engine).
public enum NutritionKit {
    private static let minimumIntakeDaysForColdStart = 5

    /// Reconcile weekly intake and trend weight into an updated TDEE estimate.
    @discardableResult
    public static func updateTrend(
        state: inout NutritionTrendState,
        weekDays: [NutritionTrendDayInput],
        defaultBodyMassKg: Double = 75
    ) -> NutritionTrendState {
        guard !weekDays.isEmpty else { return state }

        let sorted = weekDays.sorted { $0.helmDay < $1.helmDay }
        let weights = sorted.compactMap(\.bodyMassKg).filter { $0 > 1 }
        if !weights.isEmpty {
            state.smoothedTrendWeightKg = TrendWeightSmoother.ewma(weights)
        }

        let intakes = sorted.compactMap(\.loggedIntakeKcal)
        guard !intakes.isEmpty else { return state }

        let averageIntake = intakes.reduce(0, +) / Double(intakes.count)
        state.weeklyIntakeAverageKcal = averageIntake

        let mass = NutritionMass.resolved(state.smoothedTrendWeightKg, default: defaultBodyMassKg)
        var estimate = state.estimatedTDEEKcal ?? TDEECalculator.seedTDEE(bodyMassKg: mass)

        if
            intakes.count >= minimumIntakeDaysForColdStart,
            let currentTrend = state.smoothedTrendWeightKg,
            let priorTrend = state.priorWeekTrendWeightKg,
            currentTrend > 1,
            priorTrend > 1
        {
            let weightChangeKg = currentTrend - priorTrend
            let implied = TDEECalculator.impliedTDEE(
                averageIntakeKcal: averageIntake,
                weightChangeKg: weightChangeKg
            )
            estimate = TDEECalculator.blendedEstimate(prior: estimate, implied: implied)
        } else if intakes.count >= minimumIntakeDaysForColdStart {
            estimate = TDEECalculator.blendedEstimate(prior: estimate, implied: averageIntake)
        }

        state.estimatedTDEEKcal = NutritionMass.flooredTDEE(estimate, bodyMassKg: mass)
        state.priorWeekTrendWeightKg = state.smoothedTrendWeightKg
        state.lastWeeklyUpdate = sorted.last?.helmDay
        return state
    }

    public static func targets(
        for context: NutritionTargetContext,
        phase: PhaseGoal,
        trend: NutritionTrendState
    ) -> MacroTargets {
        MacroTargetCalculator.compute(context: context, phase: phase, trend: trend)
    }

    public static func resolvedBodyMassKg(_ bodyMassKg: Double?) -> Double {
        NutritionMass.resolved(bodyMassKg)
    }

    /// Clears invalid persisted trend values (e.g. zero body-mass EWMA) before target math.
    public static func healTrendState(_ state: inout NutritionTrendState, bodyMassKg: Double?) {
        let mass = NutritionMass.resolved(bodyMassKg)
        if let weight = state.smoothedTrendWeightKg, weight <= 1 {
            state.smoothedTrendWeightKg = nil
        }
        if let prior = state.priorWeekTrendWeightKg, prior <= 1 {
            state.priorWeekTrendWeightKg = nil
        }
        if let estimate = state.estimatedTDEEKcal {
            state.estimatedTDEEKcal = NutritionMass.flooredTDEE(estimate, bodyMassKg: mass)
        }
    }
}
