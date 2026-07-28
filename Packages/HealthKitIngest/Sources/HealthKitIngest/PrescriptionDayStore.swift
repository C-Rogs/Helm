import Core
import Foundation

/// Persists coach-adjusted prescriptions for a given Helm day before the workout starts.
public enum PrescriptionDayStore {
    private static let dayKey = "helm.prescription.adjusted.day"
    private static let payloadKey = "helm.prescription.adjusted.payload"

    public static func save(_ prescription: SessionPrescription, for day: HelmDay) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(prescription),
              let json = String(data: data, encoding: .utf8)
        else {
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(day.formatted, forKey: dayKey)
        defaults.set(json, forKey: payloadKey)
    }

    public static func load(for day: HelmDay) -> SessionPrescription? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dayKey) == day.formatted,
              let json = defaults.string(forKey: payloadKey),
              let data = json.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(SessionPrescription.self, from: data)
    }

    public static func clear(for day: HelmDay) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dayKey) == day.formatted else { return }
        defaults.removeObject(forKey: dayKey)
        defaults.removeObject(forKey: payloadKey)
    }

    public static func clearIfStale(currentDay: HelmDay) {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: dayKey) != currentDay.formatted {
            defaults.removeObject(forKey: dayKey)
            defaults.removeObject(forKey: payloadKey)
        }
    }
}
