import Foundation

/// Identity of a phone → Watch companion snapshot. Equal keys must not re-push WCSession.
public struct WatchCompanionPushKey: Equatable, Sendable {
    public var active: Bool
    public var exerciseName: String?
    public var setNumber: Int?
    public var setCount: Int?
    public var targetSummary: String?
    public var sessionExerciseID: String?
    public var setID: String?
    /// Unix seconds, floored. Nil when rest is not running.
    public var restEndsAt: TimeInterval?
    public var activityTypeRawValue: UInt?

    public init(
        active: Bool,
        exerciseName: String? = nil,
        setNumber: Int? = nil,
        setCount: Int? = nil,
        targetSummary: String? = nil,
        sessionExerciseID: String? = nil,
        setID: String? = nil,
        restEndsAt: TimeInterval? = nil,
        activityTypeRawValue: UInt? = nil
    ) {
        self.active = active
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.setCount = setCount
        self.targetSummary = targetSummary
        self.sessionExerciseID = sessionExerciseID
        self.setID = setID
        self.restEndsAt = restEndsAt.map { floor($0) }
        self.activityTypeRawValue = activityTypeRawValue
    }

    public static func inactive() -> WatchCompanionPushKey {
        WatchCompanionPushKey(active: false)
    }
}
