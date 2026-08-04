import Foundation
import ReadinessKit

/// Detects and stages full-week reactive deloads. Scheduled deload weeks stay automatic.
public enum ReactiveDeloadPolicy {
    public static let consecutiveDepletedThreshold = 3

    public static func shouldPropose(
        consecutiveDepletedDays: Int,
        toleranceByMuscle: [MuscleGroup: ToleranceSignals] = [:]
    ) -> Bool {
        if consecutiveDepletedDays >= consecutiveDepletedThreshold {
            return true
        }
        return toleranceByMuscle.values.contains { $0.performanceTrend == .declining }
    }

    /// Updates streak counters after today's readiness band is known.
    public static func recordReadinessDay(
        state: MesocycleState,
        band: ReadinessBand?,
        toleranceByMuscle: [MuscleGroup: ToleranceSignals] = [:]
    ) -> MesocycleState {
        var next = state
        if band == .depleted {
            next.consecutiveDepletedDays += 1
        } else if band != nil {
            next.consecutiveDepletedDays = 0
        }

        guard !isInDeloadWeek(next) else { return next }

        if shouldPropose(
            consecutiveDepletedDays: next.consecutiveDepletedDays,
            toleranceByMuscle: toleranceByMuscle
        ) {
            next.pendingReactiveDeload = true
        }
        return next
    }

    /// User confirmed a reactive deload week. Flips every muscle into deload phase.
    public static func confirmReactiveDeload(_ state: MesocycleState) -> MesocycleState {
        var next = state
        next.pendingReactiveDeload = false
        next.consecutiveDepletedDays = 0
        for muscle in next.muscles.keys {
            guard var muscleState = next.muscles[muscle] else { continue }
            muscleState.currentWeek = muscleState.blockLengthWeeks
            next.muscles[muscle] = muscleState
        }
        return next
    }

    public static func dismissPending(_ state: MesocycleState) -> MesocycleState {
        var next = state
        next.pendingReactiveDeload = false
        next.consecutiveDepletedDays = 0
        return next
    }

    public static func isInDeloadWeek(_ state: MesocycleState) -> Bool {
        state.muscles.values.contains { $0.phase == .deload }
    }
}
