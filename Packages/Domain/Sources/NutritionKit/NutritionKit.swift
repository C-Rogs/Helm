import Core
import Foundation

public enum NutritionConstants {
    public static let minimumTDEEKcal = NutritionMass.minimumTDEEKcal
}

/// Adaptive TDEE and macro targets (pure engine).
public enum NutritionKit {
    private static let minimumIntakeDaysForColdStart = 5

    /// Reconcile weekly intake and trend weight into an updated TDEE estimate.
    @discardableResult
    public static func updateTrend(
        state: inout NutritionTrendState,
        weekDays: [NutritionTrendDayInput],
        profileSeedTDEEKcal: Double?,
        defaultBodyMassKg: Double = 75
    ) -> NutritionTrendState {
        guard !weekDays.isEmpty else { return state }

        let sorted = weekDays.sorted { $0.helmDay < $1.helmDay }
        let weights = sorted.compactMap(\.bodyMassKg).filter { $0 > 1 }
        if !weights.isEmpty {
            state.smoothedTrendWeightKg = TrendWeightSmoother.robustEwma(weights)
        }

        let intakes = sorted.compactMap(\.loggedIntakeKcal)
        guard !intakes.isEmpty else { return state }

        let averageIntake = intakes.reduce(0, +) / Double(intakes.count)
        state.weeklyIntakeAverageKcal = averageIntake

        let mass = NutritionMass.resolved(
            state.smoothedTrendWeightKg ?? sorted.compactMap(\.bodyMassKg).last,
            default: defaultBodyMassKg
        )
        let profileSeed = profileSeedTDEEKcal ?? TDEECalculator.seedTDEE(bodyMassKg: mass)
        var estimate = state.estimatedTDEEKcal ?? profileSeed

        if
            intakes.count >= minimumIntakeDaysForColdStart,
            let currentTrend = state.smoothedTrendWeightKg,
            let priorTrend = state.priorWeekTrendWeightKg,
            currentTrend > 1,
            priorTrend > 1
        {
            let weightChangeKg = currentTrend - priorTrend
            if abs(weightChangeKg) > NutritionMass.stableWeightChangeThresholdKg {
                let implied = TDEECalculator.impliedTDEE(
                    averageIntakeKcal: averageIntake,
                    weightChangeKg: weightChangeKg
                )
                estimate = TDEECalculator.blendedEstimate(prior: estimate, implied: implied)
            } else if averageIntake >= profileSeed * 0.9 {
                estimate = TDEECalculator.blendedEstimate(prior: estimate, implied: averageIntake)
            }
        }

        state.estimatedTDEEKcal = NutritionMass.flooredTDEE(estimate, profileSeedTDEE: profileSeed)
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

    /// Clears invalid persisted trend values and re-anchors estimates corrupted by cut logging.
    public static func healTrendState(
        _ state: inout NutritionTrendState,
        bodyProfile: BodyProfile?
    ) {
        let profileSeed = bodyProfile.flatMap { BodyProfileTDEE.seedTDEEKcal(profile: $0) }
        let mass = NutritionMass.resolved(bodyProfile?.bodyMassKg ?? state.smoothedTrendWeightKg)

        if let weight = state.smoothedTrendWeightKg, weight <= 1 {
            state.smoothedTrendWeightKg = nil
        }
        if let prior = state.priorWeekTrendWeightKg, prior <= 1 {
            state.priorWeekTrendWeightKg = nil
        }

        if let profileSeed {
            if let estimate = state.estimatedTDEEKcal {
                state.estimatedTDEEKcal = NutritionMass.flooredTDEE(estimate, profileSeedTDEE: profileSeed)
            }

            if shouldReanchorToProfileSeed(state, profileSeed: profileSeed) {
                state.estimatedTDEEKcal = profileSeed
            }
        } else if let estimate = state.estimatedTDEEKcal {
            state.estimatedTDEEKcal = NutritionMass.flooredTDEE(estimate, bodyMassKg: mass)
        }
    }

    private static func shouldReanchorToProfileSeed(
        _ state: NutritionTrendState,
        profileSeed: Double
    ) -> Bool {
        guard
            let estimate = state.estimatedTDEEKcal,
            let intake = state.weeklyIntakeAverageKcal,
            estimate < profileSeed * 0.85,
            intake < profileSeed * 0.9
        else {
            return false
        }

        guard
            let currentTrend = state.smoothedTrendWeightKg,
            let priorTrend = state.priorWeekTrendWeightKg
        else {
            return true
        }

        // Keep a lowered estimate only when weight loss supports it.
        return currentTrend >= priorTrend - 0.05
    }
}
