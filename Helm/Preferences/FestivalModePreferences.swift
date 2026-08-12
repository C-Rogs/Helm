import Core
import Foundation
import Observation

@MainActor
@Observable
final class FestivalModePreferences {
    static let shared = FestivalModePreferences()

    static let isFestivalModeEnabledKey = TrainPreferencePersistence.festivalModeEnabledKey

    var isFestivalModeEnabled: Bool {
        didSet {
            guard !isHydrating else { return }
            persist()
        }
    }

    private let defaults: UserDefaults
    private var isHydrating = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isFestivalModeEnabled = TrainPreferencePersistence.loadBool(
            key: Self.isFestivalModeEnabledKey,
            defaults: defaults,
            defaultValue: false
        )
        isHydrating = false
    }

    private func persist() {
        TrainPreferencePersistence.saveBool(
            isFestivalModeEnabled,
            key: Self.isFestivalModeEnabledKey,
            defaults: defaults
        )
    }
}
