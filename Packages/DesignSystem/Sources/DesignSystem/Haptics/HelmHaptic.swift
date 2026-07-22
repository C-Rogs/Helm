import Foundation

public enum HelmHaptic: String, Sendable, CaseIterable {
    case readinessReveal
    case phaseChange
    case thresholdInsight
    case setLogged
    case restCountIn
    case restDone
    case prHit
    case sessionFinished
    case mealConfirmed
    case coachAdjust
    case clampRejected
    case selection

    var resourceName: String? {
        switch self {
        case .readinessReveal, .phaseChange, .thresholdInsight, .restCountIn, .restDone,
             .prHit, .sessionFinished, .clampRejected:
            rawValue
        case .setLogged, .coachAdjust, .mealConfirmed, .selection:
            nil
        }
    }
}
