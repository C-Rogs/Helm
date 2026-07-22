import Core
import DesignSystem
import Foundation

@MainActor
final class ReadinessRevealStore {
    private let defaults: UserDefaults
    private let storageKey = "helm.readinessReveal.lastDay"
    private var gate: DailyRevealGate

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        gate = DailyRevealGate(lastRevealedDay: defaults.string(forKey: storageKey))
    }

    func shouldReveal(for day: HelmDay) -> Bool {
        gate.shouldReveal(for: day.formatted)
    }

    func markRevealed(for day: HelmDay) {
        gate.markRevealed(for: day.formatted)
        defaults.set(day.formatted, forKey: storageKey)
    }
}
