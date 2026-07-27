import Core
import DesignSystem
import Foundation

/// Remembers when Cameron finished or discarded today's prescription so we do not resurrect stale shells.
@MainActor
final class PrescriptionAutoStartStore {
    private let defaults: UserDefaults
    private let storageKey = "helm.train.suppressedAutoStartDay"
    private var gate: DailyRevealGate

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        gate = DailyRevealGate(lastRevealedDay: defaults.string(forKey: storageKey))
    }

    func shouldAutoStart(for day: HelmDay) -> Bool {
        gate.shouldReveal(for: day.formatted)
    }

    func suppressAutoStart(for day: HelmDay) {
        gate.markRevealed(for: day.formatted)
        defaults.set(day.formatted, forKey: storageKey)
    }
}
