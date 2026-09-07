/// Primary hypertrophy muscles tracked by the mesocycle engine.
public enum MuscleGroup: String, Sendable, Hashable, Codable, CaseIterable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case quads
    case hamstrings
    case glutes
    case calves
    case abs

    public var displayLabel: String {
        switch self {
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
