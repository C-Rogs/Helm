import Core
import Foundation

public enum BodyProfileTDEE {
    /// Moderate activity multiplier applied to resting metabolic rate.
    public static let activityMultiplier = 1.55

    public static func restingMetabolicRateKcal(profile: BodyProfile) -> Double? {
        guard profile.isComplete else { return nil }
        let age = profile.ageYears()
        guard age >= 13, age <= 100 else { return nil }

        let base = 10 * profile.bodyMassKg + 6.25 * profile.heightCm - 5 * Double(age)
        switch profile.biologicalSex {
        case .female:
            return base - 161
        case .male:
            return base + 5
        case .other:
            return base - 78
        }
    }

    public static func seedTDEEKcal(profile: BodyProfile) -> Double? {
        guard let bmr = restingMetabolicRateKcal(profile: profile) else { return nil }
        return bmr * activityMultiplier
    }
}
