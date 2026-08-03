import Core
import Foundation
import Testing

@Suite("FocusModePreferences persistence")
struct FocusModePreferencePersistenceTests {
    @Test("defaults to true when key missing")
    func defaultEnabled() {
        let defaults = UserDefaults(suiteName: "helm.tests.focusMode.default")!
        defer { defaults.removePersistentDomain(forName: "helm.tests.focusMode.default") }
        defaults.removeObject(forKey: TrainPreferencePersistence.focusModeEnabledKey)

        let value = TrainPreferencePersistence.loadBool(
            key: TrainPreferencePersistence.focusModeEnabledKey,
            defaults: defaults,
            defaultValue: true
        )
        #expect(value == true)
    }

    @Test("round-trips false")
    func persistFalse() {
        let suite = "helm.tests.focusMode.roundtrip"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TrainPreferencePersistence.saveBool(
            false,
            key: TrainPreferencePersistence.focusModeEnabledKey,
            defaults: defaults
        )
        let value = TrainPreferencePersistence.loadBool(
            key: TrainPreferencePersistence.focusModeEnabledKey,
            defaults: defaults,
            defaultValue: true
        )
        #expect(value == false)
    }
}
