import Core
import Foundation

/// One Helm day where the athlete asked to rebuild today's session without depleted-readiness trim.
public enum ReadinessTrimBypass {
    private static let dayKey = "helm.prescription.readinessTrimBypass.day"

    public static func activate(for day: HelmDay) {
        UserDefaults.standard.set(day.formatted, forKey: dayKey)
    }

    public static func clear(for day: HelmDay) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dayKey) == day.formatted else { return }
        defaults.removeObject(forKey: dayKey)
    }

    public static func isActive(for day: HelmDay) -> Bool {
        UserDefaults.standard.string(forKey: dayKey) == day.formatted
    }
}
