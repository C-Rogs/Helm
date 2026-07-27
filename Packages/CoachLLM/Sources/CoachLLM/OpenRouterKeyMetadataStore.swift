import Foundation

/// Metadata for a provisioned OpenRouter key (e.g. free-models-only TestFlight keys).
public final class OpenRouterKeyMetadataStore: @unchecked Sendable {
    public static let freeModelsOnlyKey = "coach.openrouterFreeModelsOnly"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var freeModelsOnly: Bool {
        get {
            lock.withLock {
                defaults.bool(forKey: Self.freeModelsOnlyKey)
            }
        }
        set {
            lock.withLock {
                defaults.set(newValue, forKey: Self.freeModelsOnlyKey)
            }
        }
    }

    public func recordProvisionedKey(freeModelsOnly: Bool?) {
        guard let freeModelsOnly else { return }
        self.freeModelsOnly = freeModelsOnly
    }

    public func clear() {
        lock.withLock {
            defaults.removeObject(forKey: Self.freeModelsOnlyKey)
        }
    }
}
