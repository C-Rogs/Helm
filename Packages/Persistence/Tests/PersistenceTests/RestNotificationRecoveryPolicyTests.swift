import Testing
@testable import Persistence

@Suite("Rest notification recovery policy")
struct RestNotificationRecoveryPolicyTests {
    @Test("recovered when active session matches expected")
    func recoveredWhenMatching() {
        let outcome = RestNotificationRecoveryPolicy.evaluate(
            expectedSessionID: "session-a",
            activeSessionID: "session-a"
        )
        #expect(outcome == .recovered(sessionID: "session-a"))
    }

    @Test("no active session when snapshot missing")
    func noActiveSession() {
        let outcome = RestNotificationRecoveryPolicy.evaluate(
            expectedSessionID: "session-a",
            activeSessionID: nil
        )
        #expect(outcome == .noActiveSession(expectedSessionID: "session-a"))
    }

    @Test("session mismatch when IDs differ")
    func sessionMismatch() {
        let outcome = RestNotificationRecoveryPolicy.evaluate(
            expectedSessionID: "session-a",
            activeSessionID: "session-b"
        )
        #expect(outcome == .sessionMismatch(expected: "session-a", active: "session-b"))
    }

    @Test("recovered when notification omits session id")
    func recoveredWithoutExpectedID() {
        let outcome = RestNotificationRecoveryPolicy.evaluate(
            expectedSessionID: nil,
            activeSessionID: "session-a"
        )
        #expect(outcome == .recovered(sessionID: "session-a"))
    }

    @Test("restart live activity when session exists but handle lost")
    func restartLiveActivityOnColdStart() {
        #expect(
            RestNotificationRecoveryPolicy.shouldRestartLiveActivity(
                hasActiveSession: true,
                hasTrackedLiveActivity: false
            )
        )
        #expect(
            !RestNotificationRecoveryPolicy.shouldRestartLiveActivity(
                hasActiveSession: true,
                hasTrackedLiveActivity: true
            )
        )
        #expect(
            !RestNotificationRecoveryPolicy.shouldRestartLiveActivity(
                hasActiveSession: false,
                hasTrackedLiveActivity: false
            )
        )
    }
}
