import Foundation

/// Pure policy for phone-driven Watch companion wake + live confirmation.
public enum WatchWorkoutLaunchPolicy: Sendable {
    /// Apple cold-wake often needs a second `startWatchApp` kick.
    public static let maxAttempts = 2

    /// Seconds to wait for HR or reachability after launch attempts.
    public static let confirmLiveTimeoutSeconds: TimeInterval = 12

    public static func shouldAttempt(attemptNumber: Int) -> Bool {
        attemptNumber >= 1 && attemptNumber <= maxAttempts
    }

    /// Whether another `startWatchApp` should run after `completedAttempt` (1-based).
    public static func shouldRetryAfter(completedAttempt: Int) -> Bool {
        completedAttempt >= 1 && completedAttempt < maxAttempts
    }

    /// Live confirmed when Watch delivered HR; reachable alone is soft success (app may still be starting).
    public static func isConfirmedLive(hasHeartRate: Bool, isReachable: Bool) -> Bool {
        hasHeartRate || isReachable
    }
}
