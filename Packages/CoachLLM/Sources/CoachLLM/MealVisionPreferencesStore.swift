import Foundation

public final class MealVisionPreferencesStore: @unchecked Sendable {
    public static let backendPreferenceKey = "nutrition.photoVisionBackend"
    public static let qualityPreferenceKey = "nutrition.photoVisionQuality"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var backendPreference: MealVisionBackendPreference {
        get {
            lock.withLock {
                guard
                    let raw = defaults.string(forKey: Self.backendPreferenceKey),
                    let preference = MealVisionBackendPreference(rawValue: raw)
                else {
                    return .auto
                }
                return preference
            }
        }
        set {
            lock.withLock {
                defaults.set(newValue.rawValue, forKey: Self.backendPreferenceKey)
            }
        }
    }

    public var qualityPreference: MealVisionQualityPreference {
        get {
            lock.withLock {
                guard
                    let raw = defaults.string(forKey: Self.qualityPreferenceKey),
                    let preference = MealVisionQualityPreference(rawValue: raw)
                else {
                    return .accurate
                }
                return preference
            }
        }
        set {
            lock.withLock {
                defaults.set(newValue.rawValue, forKey: Self.qualityPreferenceKey)
            }
        }
    }

    public var geminiModelCandidates: [GeminiModel] {
        switch qualityPreference {
        case .accurate:
            [.flash, .flashLite]
        case .fast:
            [.flashLite, .flash]
        }
    }
}
