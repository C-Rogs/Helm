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
    /// Training history used for landmark seeding (`TrainingExperience` raw value).
    public var experienceRaw: String
    public var progressionGoal: ProgressionGoal
    /// Free-form emphasis such as "arms" or "v-taper"; optional coach prose.
    public var emphasis: String?
    /// Structured focus muscles (`MuscleGroup.rawValue`), max 3. Engine redistributes volume.
    public var musclePriorities: [String]
    /// Free-text request for a different plan option, shown on the cards screen.
    public var discussionNote: String?

    public init(
        confirmedMaintenanceKcal: Double? = nil,
        usesComputedEstimate: Bool = true,
        daysPerWeek: Int = 3,
        sessionDurationMinutes: Int = 60,
        experienceRaw: String = "intermediate",
        progressionGoal: ProgressionGoal = .hypertrophy,
        emphasis: String? = nil,
        musclePriorities: [String] = [],
        discussionNote: String? = nil
    ) {
        self.confirmedMaintenanceKcal = confirmedMaintenanceKcal
        self.usesComputedEstimate = usesComputedEstimate
        self.daysPerWeek = min(max(daysPerWeek, 2), 6)
        self.sessionDurationMinutes = sessionDurationMinutes
        self.experienceRaw = experienceRaw
        self.progressionGoal = progressionGoal
        self.emphasis = emphasis
        self.musclePriorities = PhaseGoal.normalizedMusclePriorities(musclePriorities)
        self.discussionNote = discussionNote
    }

    enum CodingKeys: String, CodingKey {
        case confirmedMaintenanceKcal
        case usesComputedEstimate
        case daysPerWeek
        case sessionDurationMinutes
        case experienceRaw
        case progressionGoal
        case emphasis
        case musclePriorities
        case discussionNote
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        confirmedMaintenanceKcal = try container.decodeIfPresent(Double.self, forKey: .confirmedMaintenanceKcal)
        usesComputedEstimate = try container.decodeIfPresent(Bool.self, forKey: .usesComputedEstimate) ?? true
        daysPerWeek = min(max(try container.decodeIfPresent(Int.self, forKey: .daysPerWeek) ?? 3, 2), 6)
        sessionDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionDurationMinutes) ?? 60
        experienceRaw = try container.decodeIfPresent(String.self, forKey: .experienceRaw) ?? "intermediate"
        progressionGoal = try container.decodeIfPresent(ProgressionGoal.self, forKey: .progressionGoal) ?? .hypertrophy
        emphasis = try container.decodeIfPresent(String.self, forKey: .emphasis)
        musclePriorities = PhaseGoal.normalizedMusclePriorities(
            try container.decodeIfPresent([String].self, forKey: .musclePriorities) ?? []
        )
        discussionNote = try container.decodeIfPresent(String.self, forKey: .discussionNote)
    }
}
