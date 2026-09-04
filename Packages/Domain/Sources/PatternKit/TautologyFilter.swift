import Foundation

public enum TautologyFilter {
    /// Engine-internal scoring edges. Raw outcomes that duplicate these are suppressed.
    public static func shouldSuppress(_ spec: HypothesisSpec) -> Bool {
        let exp = spec.exposure.field
        let out = spec.outcome.field

        if isReadinessInput(exp) && (out == .arcBand || out == .arcScore) {
            return true
        }
        if (exp == .hrvSdnn || exp == .arcBand || exp == .arcScore)
            && (out == .workoutMinutes || out == .hardSetCount || out == .sessionVolumeKg) {
            return true
        }
        if exp == .sleepAsleepMin && out == .arcBand {
            return true
        }
        return false
    }

    private static func isReadinessInput(_ field: DayFeatureField) -> Bool {
        switch field {
        case .sleepAsleepMin, .hrvSdnn, .restingHr, .priorDayTrimp:
            true
        default:
            false
        }
    }
}
