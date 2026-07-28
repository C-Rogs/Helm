import Foundation

public enum HelmHaptic: Sendable, Hashable, Equatable {
    case readinessReveal
    case phaseChange
    case thresholdInsight
    case setLogged
    case restCountInStep(remainingSeconds: Int)
    case restDone
    case prHit
    case sessionFinished
    case mealConfirmed
    case coachAdjust
    case clampRejected
    case selection

    /// Representative cases for tests and compile-time coverage.
    public static let allCases: [HelmHaptic] = [
        .readinessReveal,
        .phaseChange,
        .thresholdInsight,
        .setLogged,
        .restCountInStep(remainingSeconds: 5),
        .restCountInStep(remainingSeconds: 1),
        .restDone,
        .prHit,
        .sessionFinished,
        .mealConfirmed,
        .coachAdjust,
        .clampRejected,
        .selection
    ]

    var resourceName: String? {
        switch self {
        case .readinessReveal: "readinessReveal"
        case .phaseChange: "phaseChange"
        case .thresholdInsight: "thresholdInsight"
        case .restDone: "restDone"
        case .prHit: "prHit"
        case .sessionFinished: "sessionFinished"
        case .clampRejected: "clampRejected"
        case .setLogged, .coachAdjust, .mealConfirmed, .selection, .restCountInStep:
            nil
        }
    }

    var diagnosticName: String {
        switch self {
        case .restCountInStep(let remainingSeconds):
            "restCountInStep(\(remainingSeconds))"
        case .readinessReveal: "readinessReveal"
        case .phaseChange: "phaseChange"
        case .thresholdInsight: "thresholdInsight"
        case .setLogged: "setLogged"
        case .restDone: "restDone"
        case .prHit: "prHit"
        case .sessionFinished: "sessionFinished"
        case .mealConfirmed: "mealConfirmed"
        case .coachAdjust: "coachAdjust"
        case .clampRejected: "clampRejected"
        case .selection: "selection"
        }
    }
}
