import Foundation

enum TrendWeightSmoother {
    static let halfLifeDays = 10.0

    static var alpha: Double {
        1.0 - exp(log(0.5) / halfLifeDays)
    }

    static func ewma(_ values: [Double], alpha: Double = alpha) -> Double? {
        guard let first = values.first else { return nil }
        var smoothed = first
        for value in values.dropFirst() {
            smoothed = alpha * value + (1 - alpha) * smoothed
        }
        return smoothed
    }
}
