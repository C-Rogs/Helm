import Foundation

/// One-time Nutrition tab tip for the multi-action food log FAB.
@MainActor
@Observable
final class FoodLogTipStore {
    nonisolated static let dismissedDefaultsKey = "helm.foodLog.tipDismissed"
    static let shared = FoodLogTipStore()

    private let defaults: UserDefaults

    private(set) var isVisible: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isVisible = !defaults.bool(forKey: Self.dismissedDefaultsKey)
    }

    func dismiss() {
        isVisible = false
        defaults.set(true, forKey: Self.dismissedDefaultsKey)
    }
}
