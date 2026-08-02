import Foundation

/// Persistence helpers for Train settings (UserDefaults-backed).
public enum TrainPreferencePersistence {
    public static let workoutFeedbackEnabledKey = "helm.train.workoutFeedbackEnabled"
    public static let restTimerSoundEnabledKey = "helm.train.restTimerSoundEnabled"
    public static let restTimerSoundIDKey = "helm.train.restTimerSoundID"
    public static let restTimerVolumeKey = "helm.train.restTimerVolume"

    public static func loadBool(
        key: String,
        defaults: UserDefaults,
        defaultValue: Bool
    ) -> Bool {
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    public static func saveBool(_ value: Bool, key: String, defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }

    public static func loadString(
        key: String,
        defaults: UserDefaults,
        defaultValue: String
    ) -> String {
        defaults.string(forKey: key) ?? defaultValue
    }

    public static func saveString(_ value: String, key: String, defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }

    public static func loadDouble(
        key: String,
        defaults: UserDefaults,
        defaultValue: Double
    ) -> Double {
        if defaults.object(forKey: key) == nil {
            return defaultValue
        }
        return defaults.double(forKey: key)
    }

    public static func saveDouble(_ value: Double, key: String, defaults: UserDefaults) {
        defaults.set(value, forKey: key)
    }
}

/// Rest-end alert sound choices (Hevy-style picker).
public enum RestTimerSoundID: String, Sendable, Codable, CaseIterable, Identifiable {
    case boxingBell
    case chime
    case beep

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .boxingBell: "Boxing bell"
        case .chime: "Chime"
        case .beep: "Beep"
        }
    }
}

/// Discrete volume levels for rest timer playback.
public enum RestTimerVolumeLevel: String, Sendable, Codable, CaseIterable, Identifiable {
    case off
    case low
    case normal
    case high

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }

    public var playerVolume: Float {
        switch self {
        case .off: 0
        case .low: 0.35
        case .normal: 0.7
        case .high: 1.0
        }
    }

    public var isEnabled: Bool { self != .off }
}
