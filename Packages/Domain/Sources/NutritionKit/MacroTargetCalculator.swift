import Core
import Foundation

public struct NutritionTargetContext: Sendable, Hashable, Equatable {
    public let bodyProfile: BodyProfile?
    public let dayType: NutritionDayType
    public let loggedDay: NutritionDay?

    public var bodyMassKg: Double? { bodyProfile?.bodyMassKg }

    public var profileSeedTDEEKcal: Double? {
        guard let bodyProfile, bodyProfile.isComplete else { return nil }
        return BodyProfileTDEE.seedTDEEKcal(profile: bodyProfile)
    }

    public init(bodyProfile: BodyProfile? = nil, dayType: NutritionDayType, loggedDay: NutritionDay? = nil) {
        self.bodyProfile = bodyProfile
        self.dayType = dayType
        self.loggedDay = loggedDay
    }

    /// Legacy helper for tests that only supply body mass.
    public init(bodyMassKg: Double?, dayType: NutritionDayType, loggedDay: NutritionDay? = nil) {
        if let bodyMassKg, bodyMassKg > 1 {
            let calendar = Calendar(identifier: .gregorian)
            let dob = calendar.date(byAdding: .year, value: -30, to: Date()) ?? Date()
            self.bodyProfile = BodyProfile(
                bodyMassKg: bodyMassKg,
                heightCm: 175,
                biologicalSex: .male,
                dateOfBirth: dob
            )
        } else {
            self.bodyProfile = nil
        }
        self.dayType = dayType
        self.loggedDay = loggedDay
    }
}

enum MacroTargetCalculator {
    static let proteinGramsPerKg = 2.0

    static func phaseCalorieAdjustment(for phase: PhaseGoal) -> Double {
        let kcalPerDayPerKgWeek = TDEECalculator.kcalPerKgBodyMassChange / 7.0
        switch phase.phase {
        case .cut:
            let rate = validatedWeeklyRate(phase.weeklyRateKg, default: 0.5)
            return rate * kcalPerDayPerKgWeek
        case .gain:
            let rate = validatedWeeklyRate(phase.weeklyRateKg, default: 0.25)
            return -rate * kcalPerDayPerKgWeek
        case .maintain:
            return 0
        }
    }

    private static func validatedWeeklyRate(_ rate: Double?, default defaultRate: Double) -> Double {
        guard let rate, rate.isFinite, rate > 0 else { return defaultRate }
        return min(rate, 1.0)
    }

    static func resolvedTDEE(
        trend: NutritionTrendState,
        profileSeedTDEE: Double,
        bodyMassKg: Double
    ) -> Double {
        let rawEstimate = trend.estimatedTDEEKcal.flatMap { $0 > 0 ? $0 : nil } ?? profileSeedTDEE
        let floored = NutritionMass.flooredTDEE(rawEstimate, profileSeedTDEE: profileSeedTDEE)
        return floored.isFinite ? floored : profileSeedTDEE
    }

    static func carbShare(for dayType: NutritionDayType) -> Double {
        switch dayType {
        case .training:
            0.45
        case .rest, .deload:
            0.35
        }
    }

    static func compute(
        context: NutritionTargetContext,
        phase: PhaseGoal,
        trend: NutritionTrendState
    ) -> MacroTargets {
        guard
            let profile = context.bodyProfile,
            profile.isComplete,
            profile.ageYears() >= 13,
            let profileSeed = context.profileSeedTDEEKcal
        else {
            return .pending(dayType: context.dayType, loggedDay: context.loggedDay)
        }

        let mass = profile.bodyMassKg
        let tdee = resolvedTDEE(trend: trend, profileSeedTDEE: profileSeed, bodyMassKg: mass)
        let proteinGrams = Int((mass * proteinGramsPerKg).rounded())
        let proteinKcal = proteinGrams * 4
        let desiredCalories = Int((tdee - phaseCalorieAdjustment(for: phase)).rounded())
        let minimumFatGrams = Int((mass * 0.6).rounded(.up))
        let targetCalories = max(
            desiredCalories,
            proteinKcal + minimumFatGrams * 9,
            Int(NutritionMass.minimumTDEEKcal.rounded())
        )

        let remainingKcal = max(targetCalories - proteinKcal, 0)
        let carbShare = carbShare(for: context.dayType)
        let desiredCarbKcal = Int((Double(remainingKcal) * carbShare).rounded())
        let fatGrams = min(
            max(Int((Double(remainingKcal - desiredCarbKcal) / 9.0).rounded()), minimumFatGrams),
            remainingKcal / 9
        )
        let carbohydrateGrams = max(Int((Double(remainingKcal - fatGrams * 9) / 4.0).rounded()), 0)
        let macroCalories = proteinKcal + carbohydrateGrams * 4 + fatGrams * 9
        let reconciledCalories = abs(macroCalories - targetCalories) <= 4 ? targetCalories : macroCalories

        return MacroTargets(
            caloriesKcal: reconciledCalories,
            proteinGrams: proteinGrams,
            carbohydrateGrams: carbohydrateGrams,
            fatGrams: fatGrams,
            dayType: context.dayType,
            estimatedTDEEKcal: Int(tdee.rounded()),
            macroGapKilocalories: context.loggedDay.flatMap(MacroGapCalculator.macroGap(for:))
        )
    }
}

extension MacroTargets {
    static func pending(dayType: NutritionDayType, loggedDay: NutritionDay?) -> MacroTargets {
        MacroTargets(
            caloriesKcal: 0,
            proteinGrams: 0,
            carbohydrateGrams: 0,
            fatGrams: 0,
            dayType: dayType,
            estimatedTDEEKcal: 0,
            macroGapKilocalories: loggedDay.flatMap(MacroGapCalculator.macroGap(for:))
        )
    }
}
