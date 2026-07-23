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
        let weights = sorted.compactMap(\.bodyMassKg)
        if !weights.isEmpty {
            state.smoothedTrendWeightKg = TrendWeightSmoother.ewma(weights)
        }

        let intakes = sorted.compactMap(\.loggedIntakeKcal)
        guard !intakes.isEmpty else { return state }

        let averageIntake = intakes.reduce(0, +) / Double(intakes.count)
        state.weeklyIntakeAverageKcal = averageIntake

        let mass = state.smoothedTrendWeightKg ?? defaultBodyMassKg
        var estimate = state.estimatedTDEEKcal ?? TDEECalculator.seedTDEE(bodyMassKg: mass)

        if
            let currentTrend = state.smoothedTrendWeightKg,
            let priorTrend = state.priorWeekTrendWeightKg
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

        state.estimatedTDEEKcal = estimate
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
}
