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
    /// Today's meal buckets, logged totals, and macro targets for nutrition Q&A.
    public let nutritionDiary: String

    public init(
        readinessBaselines: String = "",
        evidence: [EvidenceRecord] = [],
        recent: [CoachContextDay] = [],
        recentWorkouts: String = "",
        trainingPlanSnapshot: String = "",
        nutritionDiary: String = ""
    ) {
        self.readinessBaselines = readinessBaselines
        self.evidence = evidence
        self.recent = recent
        self.recentWorkouts = recentWorkouts
        self.trainingPlanSnapshot = trainingPlanSnapshot
        self.nutritionDiary = nutritionDiary
    }

    public static let empty = CoachContextDays()
}
