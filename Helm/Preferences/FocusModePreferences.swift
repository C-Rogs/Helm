import Core
import Foundation
import Observation

@MainActor
@Observable
final class FocusModePreferences {
    static let shared = FocusModePreferences()

    static let isFocusModeEnabledKey = TrainPreferencePersistence.focusModeEnabledKey

    var isFocusModeEnabled: Bool {
        didSet {
            guard !isHydrating else { return }
            persist()
        }
    }

    private let defaults: UserDefaults
    private var isHydrating = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isFocusModeEnabled = TrainPreferencePersistence.loadBool(
            key: Self.isFocusModeEnabledKey,
            defaults: defaults,
            defaultValue: true
        )
        isHydrating = false
    }

    private func persist() {
        TrainPreferencePersistence.saveBool(
            isFocusModeEnabled,
            key: Self.isFocusModeEnabledKey,
            defaults: defaults
        )
    }
}
