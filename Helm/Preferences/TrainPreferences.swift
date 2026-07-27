import Foundation
import Observation

@MainActor
@Observable
final class TrainPreferences {
    static let shared = TrainPreferences()

    static let workoutFeedbackEnabledKey = "helm.train.workoutFeedbackEnabled"
    static let restTimerSoundEnabledKey = "helm.train.restTimerSoundEnabled"

    var workoutFeedbackEnabled: Bool {
        didSet { persist() }
    }

    var restTimerSoundEnabled: Bool {
        didSet { persist() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.workoutFeedbackEnabledKey) == nil {
            workoutFeedbackEnabled = true
        } else {
            workoutFeedbackEnabled = defaults.bool(forKey: Self.workoutFeedbackEnabledKey)
        }
        if defaults.object(forKey: Self.restTimerSoundEnabledKey) == nil {
            restTimerSoundEnabled = true
        } else {
            restTimerSoundEnabled = defaults.bool(forKey: Self.restTimerSoundEnabledKey)
        }
    }

    private func persist() {
        defaults.set(workoutFeedbackEnabled, forKey: Self.workoutFeedbackEnabledKey)
        defaults.set(restTimerSoundEnabled, forKey: Self.restTimerSoundEnabledKey)
    }
}
