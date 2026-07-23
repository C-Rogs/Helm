import Foundation

public final class ProviderPreferencesStore: @unchecked Sendable {
    public static let selectedProviderKey = "coach.selectedProvider"

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var selectedProvider: ProviderKind {
        get {
            lock.withLock {
                guard let raw = defaults.string(forKey: Self.selectedProviderKey),
                      let kind = ProviderKind(rawValue: raw)
                else {
                    return .gemini
                }
                return kind
            }
        }
        set {
            lock.withLock {
                defaults.set(newValue.rawValue, forKey: Self.selectedProviderKey)
            }
        }
    }
}
