import Foundation

/// Persistence helpers for Train settings (UserDefaults-backed).
public enum TrainPreferencePersistence {
    public static let workoutFeedbackEnabledKey = "helm.train.workoutFeedbackEnabled"
    public static let restTimerSoundEnabledKey = "helm.train.restTimerSoundEnabled"

    public static func loadBool(
        key: String,
        defaults: UserDefaults,
        defaultValue: Bool
    ) -> Bool {
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    public static func saveBool(_ value: Bool, key: String, defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }
}
