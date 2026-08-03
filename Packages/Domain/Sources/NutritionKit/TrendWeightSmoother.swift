import Foundation

public enum TrendWeightSmoother {
    public static let halfLifeDays = 10.0
    public static let hampelWindow = 7
    public static let hampelThreshold = 3.0
    /// Consistency factor so MAD approximates a normal-distribution sigma.
    public static let madScale = 1.4826
    /// Floor so flat baselines (MAD ≈ 0) still reject 1-2 kg water spikes.
    public static let minimumMADKg = 0.2

    public static var alpha: Double {
        1.0 - exp(log(0.5) / halfLifeDays)
    }

    public static func ewma(_ values: [Double], alpha: Double = alpha) -> Double? {
        guard let first = values.first else { return nil }
        var smoothed = first
        for value in values.dropFirst() {
            smoothed = alpha * value + (1 - alpha) * smoothed
        }
        return smoothed
    }

    /// Rolling Hampel filter: replace outliers with the window median; keep series length.
    public static func hampelFilter(
        _ values: [Double],
        window: Int = hampelWindow,
        threshold: Double = hampelThreshold
    ) -> [Double] {
        guard !values.isEmpty else { return [] }
        let oddWindow = max(1, window % 2 == 0 ? window + 1 : window)
        let half = oddWindow / 2
        var result = values

        for index in values.indices {
            let lower = max(0, index - half)
            let upper = min(values.count - 1, index + half)
            let slice = Array(values[lower ... upper])
            let med = median(slice)
            let deviations = slice.map { abs($0 - med) }
            let mad = max(median(deviations), minimumMADKg)
            let limit = threshold * madScale * mad
            if abs(values[index] - med) > limit {
                result[index] = med
            }
        }
        return result
    }

    /// Hampel outlier rejection then EWMA (same half-life as `ewma`).
    public static func robustEwma(
        _ values: [Double],
        window: Int = hampelWindow,
        threshold: Double = hampelThreshold,
        alpha: Double = alpha
    ) -> Double? {
        ewma(hampelFilter(values, window: window, threshold: threshold), alpha: alpha)
    }

    /// Chronological series after Hampel; caller applies EWMA step-by-step for charts.
    public static func filteredSeries(
        _ values: [Double],
        window: Int = hampelWindow,
        threshold: Double = hampelThreshold
    ) -> [Double] {
        hampelFilter(values, window: window, threshold: threshold)
    }

    private static func median(_ values: [Double]) -> Double {
        precondition(!values.isEmpty)
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
