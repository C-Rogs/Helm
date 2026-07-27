import Foundation

public enum TrendWeightSmoother {
    public static let halfLifeDays = 10.0

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
}
