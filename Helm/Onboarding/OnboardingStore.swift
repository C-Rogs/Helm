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
        CloudBackupCoordinator.shared.schedulePush()
    }

    func applyCompleted(_ completed: Bool) {
        isCompleted = completed
        defaults.set(completed, forKey: Self.completedDefaultsKey)
    }

    func syncFromDefaults() {
        isCompleted = defaults.bool(forKey: Self.completedDefaultsKey)
    }
}
