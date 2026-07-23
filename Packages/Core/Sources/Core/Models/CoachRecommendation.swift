import Foundation

public enum CoachRecommendationScope: String, Codable, Sendable, CaseIterable {
    case session
    case exercise
    case set
}

public enum CoachRecommendationType: String, Codable, Sendable, CaseIterable {
    case sessionAdjustment = "session_adjustment"
}

public struct StoredCoachRecommendation: Sendable, Hashable, Identifiable, Equatable {
    public let id: String
    public let scope: CoachRecommendationScope
    public let workoutSessionID: String?
    public let workoutSessionExerciseID: String?
    public let setEntryID: String?
    public let recommendationType: CoachRecommendationType
    public let payloadJSON: String
    public let confidence: Double?
    public let modelVersion: String?
    public let generatedAt: Date
    public let actedOnAt: Date?
    public let dismissedAt: Date?

    public init(
        id: String,
        scope: CoachRecommendationScope,
        workoutSessionID: String?,
        workoutSessionExerciseID: String? = nil,
        setEntryID: String? = nil,
        recommendationType: CoachRecommendationType,
        payloadJSON: String,
        confidence: Double? = nil,
        modelVersion: String? = nil,
        generatedAt: Date,
        actedOnAt: Date? = nil,
        dismissedAt: Date? = nil
    ) {
        self.id = id
        self.scope = scope
        self.workoutSessionID = workoutSessionID
        self.workoutSessionExerciseID = workoutSessionExerciseID
        self.setEntryID = setEntryID
        self.recommendationType = recommendationType
        self.payloadJSON = payloadJSON
        self.confidence = confidence
        self.modelVersion = modelVersion
        self.generatedAt = generatedAt
        self.actedOnAt = actedOnAt
        self.dismissedAt = dismissedAt
    }
}

public struct CoachRecommendationInsert: Sendable, Equatable {
    public let scope: CoachRecommendationScope
    public let workoutSessionID: String?
    public let workoutSessionExerciseID: String?
    public let setEntryID: String?
    public let recommendationType: CoachRecommendationType
    public let payloadJSON: String
    public let confidence: Double?
    public let modelVersion: String?

    public init(
        scope: CoachRecommendationScope,
        workoutSessionID: String?,
        workoutSessionExerciseID: String? = nil,
        setEntryID: String? = nil,
        recommendationType: CoachRecommendationType,
        payloadJSON: String,
        confidence: Double? = nil,
        modelVersion: String? = nil
    ) {
        self.scope = scope
        self.workoutSessionID = workoutSessionID
        self.workoutSessionExerciseID = workoutSessionExerciseID
        self.setEntryID = setEntryID
        self.recommendationType = recommendationType
        self.payloadJSON = payloadJSON
        self.confidence = confidence
        self.modelVersion = modelVersion
    }
}

public struct SessionAdjustmentBannerModel: Sendable, Hashable, Equatable {
    public let fromLabel: String
    public let toLabel: String
    public let reason: String
    public let recommendationID: String

    public init(fromLabel: String, toLabel: String, reason: String, recommendationID: String) {
        self.fromLabel = fromLabel
        self.toLabel = toLabel
        self.reason = reason
        self.recommendationID = recommendationID
    }
}
