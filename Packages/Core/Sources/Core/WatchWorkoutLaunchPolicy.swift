import Foundation

/// Pure policy for phone-driven Watch companion wake + live confirmation.
public enum WatchWorkoutLaunchPolicy: Sendable {
    /// Always fire this many `startWatchApp` kicks (Apple cold-wake pattern).
    public static let maxAttempts = 4

    /// Delay between kicks so Watch has time to continue a half-started wake.
    public static let retryDelaySeconds: TimeInterval = 0.75

    /// Seconds to wait for HR after launch attempts.
    public static let confirmLiveTimeoutSeconds: TimeInterval = 16

    public static func shouldAttempt(attemptNumber: Int) -> Bool {
        attemptNumber >= 1 && attemptNumber <= maxAttempts
    }

    /// Always double-kick. First `success` often means system queued a notification
    /// only; second kick is what finishes waking `handle(_:)` on a locked Watch.
    public static func shouldRetryAfter(completedAttempt: Int, attemptSucceeded: Bool) -> Bool {
        _ = attemptSucceeded
        return completedAttempt >= 1 && completedAttempt < maxAttempts
    }

    /// Live confirmed only when Watch delivered HR (reachability alone can show stale resting HR).
    public static func isConfirmedLive(hasHeartRate: Bool, isReachable: Bool) -> Bool {
        hasHeartRate
    }
}
