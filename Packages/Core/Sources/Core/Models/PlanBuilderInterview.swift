import Foundation

/// Athlete-confirmed inputs collected by the coach plan-builder interview.
///
/// Pure value type so both PlanKit (candidate generation) and Persistence
/// (session storage) can consume it without coupling.
public struct PlanBuilderInterview: Sendable, Hashable, Codable {
    public enum ProgressionGoal: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
        case strength
        case hypertrophy
        case recomposition

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .strength: "Maximal strength"
            case .hypertrophy: "Muscle growth"
            case .recomposition: "Recomposition"
            }
        }

        public var detail: String {
            switch self {
            case .strength:
                "Priority on heavy compound progression and low-rep strength peaking."
            case .hypertrophy:
                "Priority on weekly hard-set volume and stretch-position stimulus."
            case .recomposition:
                "Balanced muscle retention and fat loss with moderate volume."
            }
        }
    }

    /// Maintenance calories the athlete confirmed. `nil` keeps the computed estimate only.
    public var confirmedMaintenanceKcal: Double?
    /// Whether the shown estimate came from the TDEE calculator rather than self-report.
    public var usesComputedEstimate: Bool
    /// Training days available per week (2...6).
    public var daysPerWeek: Int
    /// Session time budget in minutes (30 / 45 / 60 / 75).
    public var sessionDurationMinutes: Int
    public var progressionGoal: ProgressionGoal
    /// Free-form emphasis such as "arms" or "v-taper"; optional.
    public var emphasis: String?

    public init(
        confirmedMaintenanceKcal: Double? = nil,
        usesComputedEstimate: Bool = true,
        daysPerWeek: Int = 3,
        sessionDurationMinutes: Int = 60,
        progressionGoal: ProgressionGoal = .hypertrophy,
        emphasis: String? = nil
    ) {
        self.confirmedMaintenanceKcal = confirmedMaintenanceKcal
        self.usesComputedEstimate = usesComputedEstimate
        self.daysPerWeek = min(max(daysPerWeek, 2), 6)
        self.sessionDurationMinutes = sessionDurationMinutes
        self.progressionGoal = progressionGoal
        self.emphasis = emphasis
    }
}
