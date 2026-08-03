import Foundation

/// Pure policy for phone-driven Watch companion wake + live confirmation.
public enum WatchWorkoutLaunchPolicy: Sendable {
    /// Max `startWatchApp` attempts when earlier attempts fail.
    public static let maxAttempts = 2

    /// Seconds to wait for HR or reachability after launch attempts.
    public static let confirmLiveTimeoutSeconds: TimeInterval = 12

    public static func shouldAttempt(attemptNumber: Int) -> Bool {
        attemptNumber >= 1 && attemptNumber <= maxAttempts
    }

    /// Whether another `startWatchApp` should run after `completedAttempt` (1-based).
    /// Retry only on failure. A successful wake must not fire a second kick.
    public static func shouldRetryAfter(completedAttempt: Int, attemptSucceeded: Bool) -> Bool {
        guard !attemptSucceeded else { return false }
        return completedAttempt >= 1 && completedAttempt < maxAttempts
    }

    /// Live confirmed when Watch delivered HR; reachable alone is soft success (app may still be starting).
    public static func isConfirmedLive(hasHeartRate: Bool, isReachable: Bool) -> Bool {
        hasHeartRate || isReachable
    }
}
