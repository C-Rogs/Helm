import Core
import Foundation
import Observation

@MainActor
@Observable
final class TrainPreferences {
    static let shared = TrainPreferences()

    static let workoutFeedbackEnabledKey = TrainPreferencePersistence.workoutFeedbackEnabledKey
    static let restTimerSoundEnabledKey = TrainPreferencePersistence.restTimerSoundEnabledKey

    var workoutFeedbackEnabled: Bool {
        didSet { persist() }
    }

    var restTimerSoundEnabled: Bool {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        workoutFeedbackEnabled = TrainPreferencePersistence.loadBool(
            key: Self.workoutFeedbackEnabledKey,
            defaults: defaults,
            defaultValue: true
        )
        restTimerSoundEnabled = TrainPreferencePersistence.loadBool(
            key: Self.restTimerSoundEnabledKey,
            defaults: defaults,
            defaultValue: true
        )
    }

    private func persist() {
        TrainPreferencePersistence.saveBool(
            workoutFeedbackEnabled,
            key: Self.workoutFeedbackEnabledKey,
            defaults: defaults
        )
        TrainPreferencePersistence.saveBool(
            restTimerSoundEnabled,
            key: Self.restTimerSoundEnabledKey,
            defaults: defaults
        )
    }
}
