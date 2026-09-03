import Core
import Foundation
import PlanKit

public enum SessionSplitKind: String, Sendable, Hashable, Codable, CaseIterable {
    case push
    case pull
    case legs
    case upper
    case lower
    case full
    case arms
    case vTaper = "v_taper"
    case armFocus = "arm_focus"
    case custom

    public var label: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .upper: "Upper"
        case .lower: "Lower"
        case .full: "Full Body"
        case .arms: "Arms"
        case .vTaper: "V-Taper"
        case .armFocus: "Arm Focus"
        case .custom: "Custom"
        }
    }

    public var muscles: [MuscleGroup] {
        switch self {
        case .push, .pull, .legs, .upper, .lower, .full, .arms:
            trainingDayKind.targetMuscles
        case .vTaper:
            [.shoulders, .back, .chest]
        case .armFocus:
            [.biceps, .triceps, .shoulders]
        case .custom:
            []
        }
    }

    public var trainingDayKind: TrainingDayKind {
        switch self {
        case .push, .vTaper: .push
        case .pull, .armFocus: .pull
        case .legs: .legs
        case .upper: .upper
        case .lower: .lower
        case .full, .custom: .full
        case .arms: .arms
        }
    }

    public init(trainingDayKind: TrainingDayKind) {
        switch trainingDayKind {
        case .push: self = .push
        case .pull: self = .pull
        case .legs: self = .legs
        case .upper: self = .upper
        case .lower: self = .lower
        case .full: self = .full
        case .arms: self = .arms
        }
    }
}

public enum SessionSplitPlanner {
    public static func splitLabel(for muscles: [MuscleGroup], emphasis: String?) -> String {
        _ = emphasis
        if let matched = matchSplitKind(for: muscles) {
            return matched.label
        }
        return muscleSummary(for: muscles)
    }

    public static func muscleSummary(for muscles: [MuscleGroup]) -> String {
        muscles.map(muscleLabel).joined(separator: " + ")
    }

    public static func matchSplitKind(for muscles: [MuscleGroup]) -> SessionSplitKind? {
        let set = Set(muscles)
        for kind in SessionSplitKind.allCases where kind != .custom {
            if Set(kind.muscles) == set {
                return kind
            }
        }
        for kind in SessionSplitKind.allCases where kind != .custom {
            let template = Set(kind.muscles)
            if !set.isDisjoint(with: template), set.isSubset(of: template.union([.calves])) {
                return kind
            }
        }
        return nil
    }

    public static func inferSplitKind(from muscles: Set<MuscleGroup>) -> SessionSplitKind? {
        inferSplitKind(
            from: muscles,
            among: [.push, .pull, .legs, .upper, .lower, .full, .arms]
        )
    }

    public static func inferSplitKind(
        from muscles: Set<MuscleGroup>,
        among candidates: [SessionSplitKind]
    ) -> SessionSplitKind? {
        guard !muscles.isEmpty else { return nil }
        let dayKinds = candidates.map(\.trainingDayKind)
        guard let match = TrainingDayKind.bestMatch(muscles: muscles, among: dayKinds) else {
            return matchSplitKind(for: Array(muscles))
        }
        return SessionSplitKind(trainingDayKind: match)
    }

    /// Remaining planned sessions this week. Callers must pass saved `daysPerWeek` (no silent 3-day default).
    public static func remainingSessionsThisWeek(completedThisWeek: Int, plannedPerWeek: Int) -> Int {
        max(1, plannedPerWeek - completedThisWeek)
    }

    private static func muscleLabel(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .abs: "Abs"
        }
    }
}
