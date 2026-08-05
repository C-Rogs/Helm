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
    @Test("unavailable when neither Watch nor phone HR session")
    func unavailable() {
        #expect(
            WatchCompanionLinkStatus.resolve(
                canDriveWatch: false,
                phoneHRActive: false,
                liveBPM: nil
            ) == .unavailable
        )
    }

    @Test("live BPM wins regardless of gates")
    func liveWins() {
        #expect(
            WatchCompanionLinkStatus.resolve(
                canDriveWatch: false,
                phoneHRActive: false,
                liveBPM: 140
            ) == .live(bpm: 140)
        )
        #expect(
            WatchCompanionLinkStatus.resolve(
                canDriveWatch: true,
                phoneHRActive: true,
                liveBPM: 128
            ) == .live(bpm: 128)
        )
    }

    @Test("connecting Watch when companion expected")
    func connectingWatch() {
        #expect(
            WatchCompanionLinkStatus.resolve(
                canDriveWatch: true,
                phoneHRActive: true,
                liveBPM: nil
            ) == .connecting(.watch)
        )
    }

    @Test("connecting phone when only phone HR session")
    func connectingPhone() {
        #expect(
            WatchCompanionLinkStatus.resolve(
                canDriveWatch: false,
                phoneHRActive: true,
                liveBPM: nil
            ) == .connecting(.phone)
        )
    }
}
