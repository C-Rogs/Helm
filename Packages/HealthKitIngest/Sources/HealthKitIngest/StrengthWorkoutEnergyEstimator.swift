import Foundation

/// Estimates active energy for strength workouts when Watch HK session is absent.
/// Used so phone-finished workouts still contribute to Apple Fitness training load.
public enum StrengthWorkoutEnergyEstimator {
    /// Default adult mass when body composition is unknown.
    public static let defaultBodyMassKilograms = 75.0
    /// MET for traditional weight training (Compendium approx).
    public static let traditionalStrengthMET = 6.0

    public static func activeEnergyKilocalories(
        startedAt: Date,
        endedAt: Date,
        bodyMassKilograms: Double? = nil
    ) -> Double {
        let hours = max(0, endedAt.timeIntervalSince(startedAt)) / 3_600
        let mass = max(40, bodyMassKilograms ?? defaultBodyMassKilograms)
        return traditionalStrengthMET * mass * hours
    }
}
