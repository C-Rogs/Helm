import Foundation

/// Top-level program shape. PPL is live; other templates reserved for later slot tables.
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
        case .upperLower: "Coming next. Uses PPL slots until tables ship."
        case .fullBody: "Coming next. Uses PPL slots until tables ship."
        }
    }

    /// Templates with dedicated composer tables. Others fall back to PPL day mapping.
    public var hasDedicatedSlotTables: Bool {
        self == .ppl
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

    public var label: String {
        rawValue.capitalized
    }

    /// Infer from legacy muscle lists when an explicit kind is absent.
    public static func infer(from muscles: [MuscleGroup]) -> TrainingDayKind {
        let set = Set(muscles)
        let leg: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves]
        let push: Set<MuscleGroup> = [.chest, .shoulders, .triceps]
        let pull: Set<MuscleGroup> = [.back, .biceps, .shoulders]
        let legOverlap = set.intersection(leg).count
        let pushOverlap = set.intersection(push).count
        let pullOverlap = set.intersection(pull).count
        if legOverlap >= 2 { return .legs }
        if pullOverlap >= 1, pullOverlap >= pushOverlap { return .pull }
        if pushOverlap >= 1 { return .push }
        return .full
    }
}
