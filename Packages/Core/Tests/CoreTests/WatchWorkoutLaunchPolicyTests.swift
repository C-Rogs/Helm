import Foundation
import Testing
@testable import Core

@Suite("WatchWorkoutLaunchPolicy")
struct WatchWorkoutLaunchPolicyTests {
    @Test("attempts 1-4 are valid; 5 is not")
    func attemptBounds() {
        #expect(WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 1))
        #expect(WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 2))
        #expect(WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 4))
        #expect(!WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 5))
        #expect(!WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 0))
    }

    @Test("always multi-kicks even after first success (Apple cold-wake)")
    func retryAfter() {
        #expect(WatchWorkoutLaunchPolicy.shouldRetryAfter(completedAttempt: 1, attemptSucceeded: true))
        #expect(WatchWorkoutLaunchPolicy.shouldRetryAfter(completedAttempt: 3, attemptSucceeded: true))
        #expect(!WatchWorkoutLaunchPolicy.shouldRetryAfter(completedAttempt: 4, attemptSucceeded: true))
        #expect(WatchWorkoutLaunchPolicy.maxAttempts == 4)
    }

    @Test("live confirm needs HR, not reachability alone")
    func confirmLive() {
        #expect(WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: true, isReachable: false))
        #expect(WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: true, isReachable: true))
        #expect(!WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: false, isReachable: true))
        #expect(!WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: false, isReachable: false))
    }
}
