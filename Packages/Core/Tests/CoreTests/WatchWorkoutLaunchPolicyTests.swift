import Foundation
import Testing
@testable import Core

@Suite("WatchWorkoutLaunchPolicy")
struct WatchWorkoutLaunchPolicyTests {
    @Test("single best-effort attempt only")
    func attemptBounds() {
        #expect(WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 1))
        #expect(!WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 2))
        #expect(!WatchWorkoutLaunchPolicy.shouldAttempt(attemptNumber: 0))
        #expect(WatchWorkoutLaunchPolicy.maxAttempts == 1)
    }

    @Test("does not multi-kick after first attempt")
    func retryAfter() {
        #expect(!WatchWorkoutLaunchPolicy.shouldRetryAfter(completedAttempt: 1, attemptSucceeded: true))
        #expect(!WatchWorkoutLaunchPolicy.shouldRetryAfter(completedAttempt: 1, attemptSucceeded: false))
    }

    @Test("live confirm needs HR, not reachability alone")
    func confirmLive() {
        #expect(WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: true, isReachable: false))
        #expect(WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: true, isReachable: true))
        #expect(!WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: false, isReachable: true))
        #expect(!WatchWorkoutLaunchPolicy.isConfirmedLive(hasHeartRate: false, isReachable: false))
    }
}

@Suite("WatchCompanionLinkStatus")
struct WatchCompanionLinkStatusTests {
    @Test("unavailable when Watch companion cannot run, even if phone HR session is live")
    func unavailableWithoutWatchApp() {
        #expect(
            WatchCompanionLinkStatus.resolve(
                canDriveWatch: false,
                liveBPM: nil
            ) == .unavailable
        )
    }

    @Test("live BPM wins regardless of gates")
    func liveWins() {
        #expect(
            WatchCompanionLinkStatus.resolve(
                canDriveWatch: false,
                liveBPM: 140
            ) == .live(bpm: 140)
        )
        #expect(
            WatchCompanionLinkStatus.resolve(
                canDriveWatch: true,
                liveBPM: 128
            ) == .live(bpm: 128)
        )
    }

    @Test("connecting Watch when companion expected")
    func connectingWatch() {
        #expect(
            WatchCompanionLinkStatus.resolve(
                canDriveWatch: true,
                liveBPM: nil
            ) == .connecting(.watch)
        )
    }
}
