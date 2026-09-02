import Foundation

/// Top-level program shape. PPL, Upper/Lower, and Full Body each have dedicated composer tables.
public enum ProgramTemplate: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case ppl
    case upperLower = "upper_lower"
    case fullBody = "full_body"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .ppl: "Push / Pull / Legs"
        case .upperLower: "Upper / Lower"
        case .fullBody: "Full Body"
        }
    }

    public var detail: String {
        switch self {
        case .ppl: "Default. Clear push vs pull patterns."
        case .upperLower: "Upper days mix press and pull. Lower days keep squat and hinge."
        case .fullBody: "Each session covers lower, press, and pull patterns."
        }
    }

    /// Templates with dedicated composer tables.
    public var hasDedicatedSlotTables: Bool {
        switch self {
        case .ppl, .upperLower, .fullBody:
            true
        }
    }

    /// Canonical week rotation when the athlete picks a template without a hybrid from plan builder.
    public func defaultDayKindRotation(daysPerWeek: Int) -> [TrainingDayKind] {
        let days = min(max(daysPerWeek, 2), 6)
        let cycle: [TrainingDayKind]
        switch self {
        case .ppl: cycle = [.push, .pull, .legs]
        case .upperLower: cycle = [.upper, .lower]
        case .fullBody: cycle = [.full]
        }
        return (0 ..< days).map { cycle[$0 % cycle.count] }
    }
}

/// Session time budget that caps pattern slots and total working sets.
public enum SessionDurationBudget: Int, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case minutes30 = 30
    case minutes45 = 45
    case minutes60 = 60
    case minutes75 = 75

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .minutes30: "30 min"
        case .minutes45: "45 min"
        case .minutes60: "60 min"
        case .minutes75: "75+ min"
        }
    }

    public var maxSlots: Int {
        switch self {
        case .minutes30: 3
        case .minutes45: 4
        case .minutes60: 5
        case .minutes75: 7
        }
    }

    public var maxTotalSets: Int {
        switch self {
        case .minutes30: 9
        case .minutes45: 14
        case .minutes60: 18
        case .minutes75: 24
        }
    }

    public var maxSetsPerSlot: Int { 4 }

    public var minimumExerciseFloor: Int {
        switch self {
        case .minutes30: 2
        case .minutes45: 3
        case .minutes60: 4
        case .minutes75: 5
        }
    }

    public static func from(minutes: Int) -> SessionDurationBudget {
        let allowed = SessionDurationBudget.allCases.map(\.rawValue)
        let closest = allowed.min(by: { abs($0 - minutes) < abs($1 - minutes) }) ?? 60
        return SessionDurationBudget(rawValue: closest) ?? .minutes60
    }
}

/// Day kind consumed by the session composer (template-agnostic).
public enum TrainingDayKind: String, Sendable, Hashable, Codable, CaseIterable {
    case push
    case pull
    case legs
    case upper
    case lower
    case full
    case arms

    public var label: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .upper: "Upper"
        case .lower: "Lower"
        case .full: "Full Body"
        case .arms: "Arms"
        }
    }

    /// Muscles the composer treats as this day's targets.
    public var targetMuscles: [MuscleGroup] {
        switch self {
        case .push: [.chest, .shoulders, .triceps]
        case .pull: [.back, .biceps, .shoulders]
        case .legs: [.quads, .hamstrings, .glutes, .calves]
        case .upper: [.chest, .back, .shoulders, .biceps, .triceps]
        case .lower: [.quads, .hamstrings, .glutes, .calves]
        case .full: MuscleGroup.allCases
        case .arms: [.biceps, .triceps, .shoulders]
        }
    }

    /// Infer from legacy muscle lists when an explicit kind is absent.
    public static func infer(from muscles: [MuscleGroup]) -> TrainingDayKind {
        bestMatch(muscles: Set(muscles), among: Array(allCases)) ?? .full
    }

    /// Tightest Jaccard match among `candidates`. Prefers smaller target sets on ties.
    public static func bestMatch(
        muscles: Set<MuscleGroup>,
        among candidates: [TrainingDayKind]
    ) -> TrainingDayKind? {
        guard !muscles.isEmpty else { return nil }
        var best: (kind: TrainingDayKind, score: Double, size: Int)?
        for kind in candidates {
            let target = Set(kind.targetMuscles)
            guard !target.isEmpty else { continue }
            let intersection = muscles.intersection(target).count
            guard intersection > 0 else { continue }
            let union = muscles.union(target).count
            let score = Double(intersection) / Double(union)
            let size = target.count
            if let current = best {
                if score > current.score + 0.001
                    || (abs(score - current.score) <= 0.001 && size < current.size) {
                    best = (kind, score, size)
                }
            } else {
                best = (kind, score, size)
            }
        }
        return best?.kind
    }
}
