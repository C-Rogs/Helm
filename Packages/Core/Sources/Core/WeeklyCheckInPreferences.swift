import Foundation

/// Shared weekly check-in weekday + training review completion stamp.
///
/// Preference keys (UserDefaults):
/// - `helm.nutrition.checkInWeekday`: Calendar weekday `1...7` (1 = Sunday ... 7 = Saturday).
///   Default: Sunday (`1`). Same key as Wave 1A `NutritionPreferencesStore.checkInWeekdayKey`.
/// - `helm.training.lastTrainingReviewOn`: `HelmDay.formatted` (`yyyy-MM-dd`) of last
///   completed Training week review ("Got it"). Separate from nutrition's
///   `helm.nutrition.lastCheckInCompletedOn`.
public enum WeeklyCheckInPreferences {
    /// Shared with nutrition check-in (Wave 1A). Do not rename without coordinating both rituals.
    public static let checkInWeekdayKey = "helm.nutrition.checkInWeekday"
    public static let lastTrainingReviewOnKey = "helm.training.lastTrainingReviewOn"

    /// Calendar weekday: Sunday. Matches `NutritionWeeklyCheckIn.defaultCheckInWeekday`.
    public static let defaultCheckInWeekday = 1

    public static func clampedWeekday(_ weekday: Int) -> Int {
        min(max(weekday, 1), 7)
    }

    public static func checkInWeekday(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: checkInWeekdayKey) as? Int
        return clampedWeekday(stored ?? defaultCheckInWeekday)
    }

    public static func setCheckInWeekday(_ weekday: Int, defaults: UserDefaults = .standard) {
        defaults.set(clampedWeekday(weekday), forKey: checkInWeekdayKey)
    }

    public static func lastTrainingReviewDay(defaults: UserDefaults = .standard) -> HelmDay? {
        guard let raw = defaults.string(forKey: lastTrainingReviewOnKey) else { return nil }
        return HelmDay(formatted: raw)
    }

    public static func recordTrainingReview(
        on day: HelmDay,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(day.formatted, forKey: lastTrainingReviewOnKey)
    }

    /// Due when today matches the shared check-in weekday and review not yet recorded for today.
    /// Mirrors `NutritionWeeklyCheckIn.isDue` with the training completion stamp.
    public static func isTrainingReviewDue(
        today: HelmDay,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let date = calendar.date(from: today.dateComponents()) else { return false }
        let todayWeekday = calendar.component(.weekday, from: date)
        let preferred = checkInWeekday(defaults: defaults)
        guard clampedWeekday(todayWeekday) == preferred else { return false }
        if let last = lastTrainingReviewDay(defaults: defaults), last >= today {
            return false
        }
        return true
    }
}
