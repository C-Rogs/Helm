import Foundation

/// Optional daily step goal. Off by default so Dashboard stays a plain step count.
///
/// Preference keys (UserDefaults):
/// - `helm.steps.goalEnabled`: Bool. Default unset / false (no nag).
/// - `helm.steps.goalCount`: Int target steps. Default `10_000` when first enabled.
public enum StepGoalPreferences {
    public static let isEnabledKey = "helm.steps.goalEnabled"
    public static let goalCountKey = "helm.steps.goalCount"

    public static let defaultGoalCount = 10_000
    public static let minGoalCount = 1_000
    public static let maxGoalCount = 50_000
    public static let goalStep = 500

    public static func clampedGoal(_ count: Int) -> Int {
        let clamped = min(max(count, minGoalCount), maxGoalCount)
        let offset = clamped - minGoalCount
        let steps = Int((Double(offset) / Double(goalStep)).rounded())
        return min(max(minGoalCount + steps * goalStep, minGoalCount), maxGoalCount)
    }

    public static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: isEnabledKey) != nil else { return false }
        return defaults.bool(forKey: isEnabledKey)
    }

    public static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: isEnabledKey)
        if enabled, defaults.object(forKey: goalCountKey) == nil {
            defaults.set(defaultGoalCount, forKey: goalCountKey)
        }
    }

    public static func goalCount(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.object(forKey: goalCountKey) as? Int
        return clampedGoal(stored ?? defaultGoalCount)
    }

    public static func setGoalCount(_ count: Int, defaults: UserDefaults = .standard) {
        defaults.set(clampedGoal(count), forKey: goalCountKey)
    }

    /// Active target when the preference is on; otherwise `nil` (plain step readout).
    public static func activeGoal(defaults: UserDefaults = .standard) -> Int? {
        guard isEnabled(defaults: defaults) else { return nil }
        return goalCount(defaults: defaults)
    }

    public static func greetingStepsLine(
        stepCount: Int,
        defaults: UserDefaults = .standard
    ) -> String {
        if let goal = activeGoal(defaults: defaults) {
            return "\(stepCount) / \(goal)"
        }
        return "\(stepCount) steps"
    }

    public static func greetingStepsAccessibilityLabel(
        stepCount: Int,
        defaults: UserDefaults = .standard
    ) -> String {
        if let goal = activeGoal(defaults: defaults) {
            return "\(stepCount) of \(goal) steps today"
        }
        return "\(stepCount) steps today"
    }
}
