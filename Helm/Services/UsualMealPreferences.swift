import Core
import Foundation

enum UsualMealPreferences {
    private enum Key {
        static let nudge = "helm.usualMeal.nudge"
        static let skipPrefix = "helm.usualMeal.skip."
        static let lastOfferPrefix = "helm.usualMeal.lastOffer."
    }

    /// Shared cooldown for automatically surfaced usual-meal proposals.
    static let nudgeCooldown: TimeInterval = 7 * 24 * 60 * 60

    static var nudgeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.nudge) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.nudge) }
    }

    static func isSkipped(day: HelmDay, bucket: MealBucket) -> Bool {
        UserDefaults.standard.bool(forKey: skipKey(day: day, bucket: bucket))
    }

    static func skip(day: HelmDay, bucket: MealBucket) {
        UserDefaults.standard.set(true, forKey: skipKey(day: day, bucket: bucket))
        markNudgeOffered(bucket: bucket)
    }

    static func clearSkip(day: HelmDay, bucket: MealBucket) {
        UserDefaults.standard.removeObject(forKey: skipKey(day: day, bucket: bucket))
    }

    static func isNudgeCoolingDown(bucket: MealBucket, now: Date = .now) -> Bool {
        guard let lastOffer = UserDefaults.standard.object(forKey: lastOfferKey(bucket: bucket)) as? Date else {
            return false
        }
        return now.timeIntervalSince(lastOffer) < nudgeCooldown
    }

    static func markNudgeOffered(bucket: MealBucket, at date: Date = .now) {
        UserDefaults.standard.set(date, forKey: lastOfferKey(bucket: bucket))
    }

    private static func skipKey(day: HelmDay, bucket: MealBucket) -> String {
        "\(Key.skipPrefix)\(day.formatted).\(bucket.rawValue)"
    }

    private static func lastOfferKey(bucket: MealBucket) -> String {
        "\(Key.lastOfferPrefix)\(bucket.rawValue)"
    }
}
