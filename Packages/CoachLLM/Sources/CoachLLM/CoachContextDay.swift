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

    public init(
        readinessBaselines: String = "",
        evidence: [EvidenceRecord] = [],
        recent: [CoachContextDay] = [],
        recentWorkouts: String = "",
        trainingPlanSnapshot: String = "",
        weekAheadSchedule: String = "",
        nutritionDiary: String = "",
        todayPrescription: String = "",
        prescriptionLoadSummary: String = "",
        volumeStateSummary: String = "",
        engineProfile: String = ""
    ) {
        self.readinessBaselines = readinessBaselines
        self.evidence = evidence
        self.recent = recent
        self.recentWorkouts = recentWorkouts
        self.trainingPlanSnapshot = trainingPlanSnapshot
        self.weekAheadSchedule = weekAheadSchedule
        self.nutritionDiary = nutritionDiary
        self.todayPrescription = todayPrescription
        self.prescriptionLoadSummary = prescriptionLoadSummary
        self.volumeStateSummary = volumeStateSummary
        self.engineProfile = engineProfile
    }

    public static let empty = CoachContextDays()
}
