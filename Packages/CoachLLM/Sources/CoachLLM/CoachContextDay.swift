import Core
import Foundation

/// One logical day's grounded context, serialized by the caller.
public struct CoachContextDay: Sendable, Hashable, Codable, Equatable {
    public let helmDay: HelmDay
    public let text: String

    public init(helmDay: HelmDay, text: String) {
        self.helmDay = helmDay
        self.text = text
    }
}

/// Recent health and training context passed into the builder.
public struct CoachContextDays: Sendable, Hashable, Codable, Equatable {
    public let readinessBaselines: String
    public let evidence: [EvidenceRecord]
    /// Evidence records grouped by module title for human-readable context formatting.
    public let groupedEvidence: [String: [EvidenceRecord]]
    public let recent: [CoachContextDay]
    public let recentWorkouts: String
    /// Engine snapshot + weekly volume ledger. Coach interprets free-form emphasis against this.
    public let trainingPlanSnapshot: String
    /// Rolling 7-day training/rest schedule including calendar busy days.
    public let weekAheadSchedule: String
    /// Today's meal buckets, logged totals, and macro targets for nutrition Q&A.
    public let nutritionDiary: String
    /// Today's engine prescription (exercises + targets) for chat negotiation.
    public let todayPrescription: String
    /// Per-lift load decisions (hold / bump / stall) for explaining prescribed weights.
    public let prescriptionLoadSummary: String
    /// Per-muscle volume state summary for coach awareness.
    public let volumeStateSummary: String
    /// Engine profile metadata: standing constraints, exercise selection inputs, active joints.
    public let engineProfile: String
    /// Active resource module titles and descriptions for the coach prompt.
    public let moduleSummaries: String
    /// Session outcome cards from recent workouts for follow-through tracking.
    public let recentSessionOutcomes: [SessionOutcomeCard]
    /// Context block freshness metadata for staleness detection.
    public let freshness: CoachContextFreshness
    public let patternFindings: String

    public init(
        readinessBaselines: String = "",
        evidence: [EvidenceRecord] = [],
        groupedEvidence: [String: [EvidenceRecord]] = [:],
        recent: [CoachContextDay] = [],
        recentWorkouts: String = "",
        trainingPlanSnapshot: String = "",
        weekAheadSchedule: String = "",
        nutritionDiary: String = "",
        todayPrescription: String = "",
        prescriptionLoadSummary: String = "",
        volumeStateSummary: String = "",
        engineProfile: String = "",
        moduleSummaries: String = "",
        recentSessionOutcomes: [SessionOutcomeCard] = [],
        freshness: CoachContextFreshness = CoachContextFreshness(),
        patternFindings: String = ""
    ) {
        self.readinessBaselines = readinessBaselines
        self.evidence = evidence
        self.groupedEvidence = groupedEvidence
        self.recent = recent
        self.recentWorkouts = recentWorkouts
        self.trainingPlanSnapshot = trainingPlanSnapshot
        self.weekAheadSchedule = weekAheadSchedule
        self.nutritionDiary = nutritionDiary
        self.todayPrescription = todayPrescription
        self.prescriptionLoadSummary = prescriptionLoadSummary
        self.volumeStateSummary = volumeStateSummary
        self.engineProfile = engineProfile
        self.moduleSummaries = moduleSummaries
        self.recentSessionOutcomes = recentSessionOutcomes
        self.freshness = freshness
        self.patternFindings = patternFindings
    }

    public static let empty = CoachContextDays()

    private enum CodingKeys: String, CodingKey {
        case readinessBaselines, evidence, groupedEvidence, recent, recentWorkouts
        case trainingPlanSnapshot, weekAheadSchedule, nutritionDiary, todayPrescription
        case prescriptionLoadSummary, volumeStateSummary, engineProfile, moduleSummaries
        case recentSessionOutcomes, freshness, patternFindings
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        readinessBaselines = try values.decode(String.self, forKey: .readinessBaselines)
        evidence = try values.decode([EvidenceRecord].self, forKey: .evidence)
        groupedEvidence = try values.decode([String: [EvidenceRecord]].self, forKey: .groupedEvidence)
        recent = try values.decode([CoachContextDay].self, forKey: .recent)
        recentWorkouts = try values.decode(String.self, forKey: .recentWorkouts)
        trainingPlanSnapshot = try values.decode(String.self, forKey: .trainingPlanSnapshot)
        weekAheadSchedule = try values.decode(String.self, forKey: .weekAheadSchedule)
        nutritionDiary = try values.decode(String.self, forKey: .nutritionDiary)
        todayPrescription = try values.decode(String.self, forKey: .todayPrescription)
        prescriptionLoadSummary = try values.decode(String.self, forKey: .prescriptionLoadSummary)
        volumeStateSummary = try values.decode(String.self, forKey: .volumeStateSummary)
        engineProfile = try values.decode(String.self, forKey: .engineProfile)
        moduleSummaries = try values.decode(String.self, forKey: .moduleSummaries)
        recentSessionOutcomes = try values.decode([SessionOutcomeCard].self, forKey: .recentSessionOutcomes)
        freshness = try values.decode(CoachContextFreshness.self, forKey: .freshness)
        patternFindings = try values.decodeIfPresent(String.self, forKey: .patternFindings) ?? ""
    }
}
