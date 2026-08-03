import Core
import Foundation
import Observation

@MainActor
@Observable
final class TrainPreferences {
    static let shared = TrainPreferences()

    static let workoutFeedbackEnabledKey = TrainPreferencePersistence.workoutFeedbackEnabledKey
    static let restTimerSoundEnabledKey = TrainPreferencePersistence.restTimerSoundEnabledKey
    static let pawelModeEnabledKey = TrainPreferencePersistence.pawelModeEnabledKey

    var workoutFeedbackEnabled: Bool {
        didSet { persist() }
    }

    /// Legacy toggle kept in sync with volume != off.
    var restTimerSoundEnabled: Bool {
        didSet {
            guard !isHydrating else { return }
            if !restTimerSoundEnabled, restTimerVolume != .off {
                restTimerVolume = .off
            } else if restTimerSoundEnabled, restTimerVolume == .off {
                restTimerVolume = .normal
            }
            persist()
        }
    }

    var restTimerSoundID: RestTimerSoundID {
        didSet {
            guard !isHydrating else { return }
            persist()
        }
    }

    var restTimerVolume: RestTimerVolumeLevel {
        didSet {
            guard !isHydrating else { return }
            restTimerSoundEnabled = restTimerVolume.isEnabled
            persist()
        }
    }

    var pawelModeEnabled: Bool {
        didSet {
            guard !isHydrating else { return }
            persist()
        }
    }

    private let defaults: UserDefaults
    private var isHydrating = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        workoutFeedbackEnabled = TrainPreferencePersistence.loadBool(
            key: Self.workoutFeedbackEnabledKey,
            defaults: defaults,
            defaultValue: true
        )
        let soundRaw = TrainPreferencePersistence.loadString(
            key: TrainPreferencePersistence.restTimerSoundIDKey,
            defaults: defaults,
            defaultValue: RestTimerSoundID.boxingBell.rawValue
        )
        restTimerSoundID = RestTimerSoundID(rawValue: soundRaw) ?? .boxingBell

        let volumeRaw = TrainPreferencePersistence.loadString(
            key: TrainPreferencePersistence.restTimerVolumeKey,
            defaults: defaults,
            defaultValue: ""
        )
        let resolvedVolume: RestTimerVolumeLevel
        if let volume = RestTimerVolumeLevel(rawValue: volumeRaw) {
            resolvedVolume = volume
        } else {
            let enabled = TrainPreferencePersistence.loadBool(
                key: Self.restTimerSoundEnabledKey,
                defaults: defaults,
                defaultValue: true
            )
            resolvedVolume = enabled ? .normal : .off
        }
        restTimerVolume = resolvedVolume
        restTimerSoundEnabled = resolvedVolume.isEnabled
        pawelModeEnabled = TrainPreferencePersistence.loadBool(
            key: Self.pawelModeEnabledKey,
            defaults: defaults,
            defaultValue: false
        )
        isHydrating = false
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
        TrainPreferencePersistence.saveString(
            restTimerSoundID.rawValue,
            key: TrainPreferencePersistence.restTimerSoundIDKey,
            defaults: defaults
        )
        TrainPreferencePersistence.saveString(
            restTimerVolume.rawValue,
            key: TrainPreferencePersistence.restTimerVolumeKey,
            defaults: defaults
        )
        TrainPreferencePersistence.saveBool(
            pawelModeEnabled,
            key: Self.pawelModeEnabledKey,
            defaults: defaults
        )
    }
}
