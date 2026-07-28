import Core
import Foundation

enum PrescriptionStaleTracker {
    private static let fingerprintKey = "helm.prescription.stale.fingerprint"
    private static let dayKey = "helm.prescription.stale.day"
    private static let dismissedDayKey = "helm.prescription.stale.dismissed"

    static func recordFingerprint(_ fingerprint: String, for day: HelmDay) {
        UserDefaults.standard.set(fingerprint, forKey: fingerprintKey)
        UserDefaults.standard.set(day.formatted, forKey: dayKey)
        UserDefaults.standard.removeObject(forKey: dismissedDayKey)
    }

    static func isStale(currentFingerprint: String, day: HelmDay) -> Bool {
        guard UserDefaults.standard.string(forKey: dayKey) == day.formatted else { return false }
        guard let stored = UserDefaults.standard.string(forKey: fingerprintKey) else { return false }
        if dismissed(for: day) { return false }
        return stored != currentFingerprint
    }

    static func dismiss(for day: HelmDay) {
        UserDefaults.standard.set(day.formatted, forKey: dismissedDayKey)
    }

    private static func dismissed(for day: HelmDay) -> Bool {
        UserDefaults.standard.string(forKey: dismissedDayKey) == day.formatted
    }

    static func staleMessage(readinessScore: Int?) -> String {
        if let readinessScore {
            return "Today's plan may be outdated after recent activity (ARC now \(readinessScore)). Coach or Regenerate below before you start."
        }
        return "Today's plan may be outdated after recent activity. Coach or Regenerate below before you start."
    }
}
