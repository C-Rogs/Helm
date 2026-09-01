import Core
import Foundation

enum UsualMealPreferences {
    private enum Key {
        static let nudge = "helm.usualMeal.nudge"
        static let skipPrefix = "helm.usualMeal.skip."
    }

    static var nudgeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Key.nudge) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Key.nudge) }
    }

    static func isSkipped(day: HelmDay, bucket: MealBucket) -> Bool {
        UserDefaults.standard.bool(forKey: skipKey(day: day, bucket: bucket))
    }

    static func skip(day: HelmDay, bucket: MealBucket) {
        UserDefaults.standard.set(true, forKey: skipKey(day: day, bucket: bucket))
    }

    static func clearSkip(day: HelmDay, bucket: MealBucket) {
        UserDefaults.standard.removeObject(forKey: skipKey(day: day, bucket: bucket))
    }

    private static func skipKey(day: HelmDay, bucket: MealBucket) -> String {
        "\(Key.skipPrefix)\(day.formatted).\(bucket.rawValue)"
    }
}
