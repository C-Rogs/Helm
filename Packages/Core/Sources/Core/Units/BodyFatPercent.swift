import Foundation

/// HealthKit `HKUnit.percent()` body-fat values arrive as a fraction (`0.145`) or
/// as a whole percent (`14.5`). Stored Helm value is always percent of body mass.
public enum BodyFatPercent: Sendable {
    public static let maximumStoredPercent: Double = 60

    public static func storedPercent(fromHealthKitPercentUnit value: Double) -> Double? {
        let raw = value <= 1 ? value * 100 : value
        guard raw > 0, raw <= maximumStoredPercent else { return nil }
        return (raw * 100).rounded() / 100
    }
}
