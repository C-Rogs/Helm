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

/// Soft PatternKit logging echoes. Alcohol max once per ISO week; office once ever.
@MainActor
@Observable
final class PatternLoggingTipStore {
    enum Tip: Equatable, Sendable {
        case alcohol
        case office
    }

    nonisolated static let alcoholWeekKey = "helm.patternTip.alcoholWeek"
    nonisolated static let officeShownKey = "helm.patternTip.officeShown"
    static let shared = PatternLoggingTipStore()

    private let defaults: UserDefaults
    private(set) var activeTip: Tip?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activeTip = nil
    }

    func noteAlcoholLogged(now: Date = Date(), calendar: Calendar = .current) {
        let year = calendar.component(.yearForWeekOfYear, from: now)
        let week = calendar.component(.weekOfYear, from: now)
        let token = "\(year)-W\(week)"
        if defaults.string(forKey: Self.alcoholWeekKey) == token {
            return
        }
        defaults.set(token, forKey: Self.alcoholWeekKey)
        activeTip = .alcohol
    }

    func noteOfficeTagged() {
        if defaults.bool(forKey: Self.officeShownKey) {
            return
        }
        defaults.set(true, forKey: Self.officeShownKey)
        activeTip = .office
    }

    func dismiss() {
        activeTip = nil
    }

    var headline: String {
        switch activeTip {
        case .alcohol:
            "Drink days now feed sleep and intake patterns."
        case .office:
            "Office days tracked against gym volume."
        case nil:
            ""
        }
    }
}

/// One-time Chat composer tip: speak with the system keyboard Dictate button.
@MainActor
@Observable
final class ChatDictateTipStore {
    nonisolated static let dismissedDefaultsKey = "helm.chat.dictateTipDismissed"
    static let shared = ChatDictateTipStore()

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
