import Foundation

public enum RestNotificationRecoveryOutcome: Equatable, Sendable {
    case recovered(sessionID: String)
    case noActiveSession(expectedSessionID: String?)
    case sessionMismatch(expected: String, active: String)
}

public enum RestNotificationRecoveryPolicy {
    public static func evaluate(
        expectedSessionID: String?,
        activeSessionID: String?
    ) -> RestNotificationRecoveryOutcome {
        guard let activeSessionID else {
            return .noActiveSession(expectedSessionID: expectedSessionID)
        }
        if let expectedSessionID, expectedSessionID != activeSessionID {
            return .sessionMismatch(expected: expectedSessionID, active: activeSessionID)
        }
        return .recovered(sessionID: activeSessionID)
    }

    public static func shouldRestartLiveActivity(
        hasActiveSession: Bool,
        hasTrackedLiveActivity: Bool
    ) -> Bool {
        hasActiveSession && !hasTrackedLiveActivity
    }
}
