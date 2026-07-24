import Foundation

public final class NutritionPreferencesStore: @unchecked Sendable {
    public static let dietarySourceModeKey = "helm.nutrition.dietarySourceMode"
    public static let shared = NutritionPreferencesStore()

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func mode() -> DietarySourceMode {
        lock.withLock {
            guard
                let raw = defaults.string(forKey: Self.dietarySourceModeKey),
                let stored = DietarySourceMode(rawValue: raw)
            else {
                return .mergeExternal
            }
            return stored
        }
    }

    public func setMode(_ mode: DietarySourceMode) {
        lock.withLock {
            defaults.set(mode.rawValue, forKey: Self.dietarySourceModeKey)
        }
    }
}
