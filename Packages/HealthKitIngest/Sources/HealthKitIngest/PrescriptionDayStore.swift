import Core
import Foundation

/// Persists coach-adjusted prescriptions for a given Helm day before the workout starts.
public enum PrescriptionDayStore {
    private static let dayKey = "helm.prescription.adjusted.day"
    private static let payloadKey = "helm.prescription.adjusted.payload"
    private static let fingerprintKey = "helm.prescription.adjusted.fingerprint"

    public static func save(
        _ prescription: SessionPrescription,
        for day: HelmDay,
        historyFingerprint: String? = nil
    ) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(prescription),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(day.formatted, forKey: dayKey)
        defaults.set(json, forKey: payloadKey)
        if let historyFingerprint {
            defaults.set(historyFingerprint, forKey: fingerprintKey)
        } else {
            defaults.removeObject(forKey: fingerprintKey)
        }
    }

    public static func load(
        for day: HelmDay,
        historyFingerprint: String? = nil
    ) -> SessionPrescription? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dayKey) == day.formatted,
              let json = defaults.string(forKey: payloadKey),
              let data = json.data(using: .utf8)
        else {
            return nil
        }
        if let historyFingerprint {
            guard defaults.string(forKey: fingerprintKey) == historyFingerprint else {
                return nil
            }
        }
        return try? JSONDecoder().decode(SessionPrescription.self, from: data)
    }

    public static func clear(for day: HelmDay) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dayKey) == day.formatted else { return }
        defaults.removeObject(forKey: dayKey)
        defaults.removeObject(forKey: payloadKey)
        defaults.removeObject(forKey: fingerprintKey)
    }

    public static func clearIfStale(currentDay: HelmDay) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: dayKey) != currentDay.formatted {
            defaults.removeObject(forKey: dayKey)
            defaults.removeObject(forKey: payloadKey)
            defaults.removeObject(forKey: fingerprintKey)
        }
    }

    /// Clear cached prescription when training history changes invalidate the adjusted plan.
    public static func invalidateIfHistoryChanged(currentFingerprint: String, for day: HelmDay) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dayKey) == day.formatted else { return }
        let stored = defaults.string(forKey: fingerprintKey)
        if stored != currentFingerprint {
            clear(for: day)
        }
    }
}
