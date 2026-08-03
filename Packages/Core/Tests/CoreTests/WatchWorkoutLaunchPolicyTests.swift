import Foundation
import Testing
@testable import Core

@Suite("WatchWorkoutLaunchPolicy")
struct WatchWorkoutLaunchPolicyTests {
    @Test("attempts 1 and 2 are valid; 3 is not")
    func attemptBounds() {
        #expect(WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 1))
        #expect(WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 2))
        #expect(!WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 3))
        #expect(!WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 0))
    }

    @Test("retries after first attempt only when it failed")
    func retryAfter() {
        #expect(WatchWorkoutLaunchPolicy.shouldRetryAfter(completedAttempt: 1, attemptSucceeded: false))
        #expect(!WatchWorkoutLaunchPolicy.shouldRetryAfter(completedAttempt: 1, attemptSucceeded: true))
        #expect(!WatchWorkoutLaunchPolicy.shouldRetryAfter(completedAttempt: 2, attemptSucceeded: false))
        #expect(WatchWorkoutLaunchPolicy.maxAttempts == 2)
    }

    @Test("live confirm needs HR or reachability")
    func confirmLive() {
        #expect(WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: true, isReachable: false))
        #expect(WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: false, isReachable: true))
        #expect(!WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: false, isReachable: false))
    }
}
