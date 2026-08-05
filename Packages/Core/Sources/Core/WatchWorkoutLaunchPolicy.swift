import Foundation

/// Pure policy for phone-driven Watch companion wake + live confirmation.
///
/// watchOS will not run third-party `handle(_:)` while the Watch is locked /
/// wrist-down. `startWatchApp` success only means healthd accepted the request.
/// Phone Train must not block on Watch; one kick is enough.
public enum WatchWorkoutLaunchPolicy: Sendable {
    /// Single best-effort handoff. Retries do not force wrist-down execution.
    public static let maxAttempts = 1

    /// Unused when `maxAttempts == 1`; kept for call-site compatibility.
    public static let retryDelaySeconds: TimeInterval = 0.75

    /// Soft window for diagnostics / first-HR logging; not a UX failure gate.
    public static let confirmLiveTimeoutSeconds: TimeInterval = 30

    public static func shouldAttempt(attemptNumber: Int) -> Bool {
        attemptNumber >= 1 && attemptNumber <= maxAttempts
    }

    public static func shouldRetryAfter(completedAttempt: Int, attemptSucceeded: Bool) -> Bool {
        _ = attemptSucceeded
        return completedAttempt >= 1 && completedAttempt < maxAttempts
    }

    /// Live confirmed only when Watch delivered HR.
    public static func isConfirmedLive(hasHeartRate: Bool, isReachable: Bool) -> Bool {
        _ = isReachable
        return hasHeartRate
    }
}
