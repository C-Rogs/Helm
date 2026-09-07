import Core
import Foundation

/// Confidence for a weekly nutrition check-in ritual (BWS-style density gates).
public enum NutritionWeeklyCheckInConfidence: String, Sendable, Hashable, Codable, Equatable {
    case high
    case moderate
    case needsData

    public var displayName: String {
        switch self {
        case .high: "High"
        case .moderate: "Moderate"
        case .needsData: "Needs data"
        }
    }
}

/// Pure helpers for the weekly nutrition check-in ritual.
public enum NutritionWeeklyCheckIn {
    public static let rollingWindowDays = 7
    public static let incompleteGoalFraction = 0.80
    public static let softGateWeighIns = 3
    public static let softGateFoodDays = 3
    public static let highGateWeighIns = 5
    public static let highGateFoodDays = 5

    /// Calendar weekday: 1 = Sunday … 7 = Saturday. Default Sunday.
    public static let defaultCheckInWeekday = 1

    public static let weekdayChoices: [(weekday: Int, name: String)] = [
        (1, "Sunday"),
        (2, "Monday"),
        (3, "Tuesday"),
        (4, "Wednesday"),
        (5, "Thursday"),
        (6, "Friday"),
        (7, "Saturday"),
    ]

    /// Inclusive rolling last-7 ending on `asOf` (not ISO week).
    public static func rollingWindow(asOf: HelmDay) -> (start: HelmDay, end: HelmDay) {
        let start = asOf.adding(days: -(rollingWindowDays - 1))
        return (start, asOf)
    }

    /// Auto-present when today matches preferred weekday and check-in not yet completed today.
    public static func isDue(
        today: HelmDay,
        todayWeekday: Int,
        preferredWeekday: Int,
        lastCompletedOn: HelmDay?
    ) -> Bool {
        let preferred = clampedWeekday(preferredWeekday)
        guard clampedWeekday(todayWeekday) == preferred else { return false }
        if let lastCompletedOn, lastCompletedOn >= today {
            return false
        }
        return true
    }

    public static func clampedWeekday(_ weekday: Int) -> Int {
        min(max(weekday, 1), 7)
    }

    public static func weekdayName(_ weekday: Int) -> String {
        weekdayChoices.first(where: { $0.weekday == clampedWeekday(weekday) })?.name ?? "Sunday"
    }

    /// Incomplete when no food logged, under 80% of goal, or logging not marked complete.
    public static func isIncomplete(
        loggedKcal: Int?,
        goalKcal: Int?,
        loggingComplete: Bool,
        hasFoodLog: Bool
    ) -> Bool {
        if !hasFoodLog { return true }
        guard let loggedKcal, loggedKcal > 0 else { return true }
        if let goalKcal, goalKcal > 0 {
            if Double(loggedKcal) < Double(goalKcal) * incompleteGoalFraction {
                return true
            }
        }
        if !loggingComplete { return true }
        return false
    }

    public static func confidence(weighInDays: Int, foodDays: Int) -> NutritionWeeklyCheckInConfidence {
        if weighInDays >= highGateWeighIns, foodDays >= highGateFoodDays {
            return .high
        }
        if weighInDays >= softGateWeighIns, foodDays >= softGateFoodDays {
            return .moderate
        }
        return .needsData
    }

    /// Default inclusion: exclude incomplete days; keep complete ones.
    public static func defaultIncluded(isIncomplete: Bool) -> Bool {
        !isIncomplete
    }

    public static func densityCounts(
        days: [(hasWeighIn: Bool, hasFoodLog: Bool, isIncluded: Bool)]
    ) -> (weighIns: Int, foodDays: Int) {
        var weighIns = 0
        var foodDays = 0
        for day in days where day.isIncluded {
            if day.hasWeighIn { weighIns += 1 }
            if day.hasFoodLog { foodDays += 1 }
        }
        return (weighIns, foodDays)
    }
}
