import Foundation

@Observable
@MainActor
final class OnboardingStore {
    nonisolated static let completedDefaultsKey = "helm.onboarding.completed"
    static let shared = OnboardingStore()

    private let defaults: UserDefaults

    private(set) var isCompleted: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isCompleted = defaults.bool(forKey: Self.completedDefaultsKey)
    }

    var shouldPresent: Bool { !isCompleted }

    func markCompleted() {
        isCompleted = true
        defaults.set(true, forKey: Self.completedDefaultsKey)
    }
}
