import Foundation

/// User preference for coach-suggested load caps during in-session adjustments.
public enum CoachLoadSafetyPreferences {
    private static let key = "helm.coach.enforceLoadSafety"

    /// When true (default), coach-suggested load increases stay within ±10% / 2.5 kg.
    public static var enforceCoachLoadCaps: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
