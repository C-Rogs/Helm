import Foundation
import Testing
@testable import Core

@Suite("WatchWorkoutActivityKind inference")
struct WatchWorkoutActivityKindInferenceTests {
    @Test("lift session stays strength")
    func liftStaysStrength() {
        #expect(
            WatchWorkoutActivityKind.inferred(
                sessionTitle: "Upper A",
                exerciseNames: ["Bench Press", "Row"],
                exerciseModes: [.weightReps, .weightReps]
            ) == .traditionalStrengthTraining
        )
    }

    @Test("mixed lift plus run stays strength")
    func mixedStaysStrength() {
        #expect(
            WatchWorkoutActivityKind.inferred(
                sessionTitle: "Upper + easy run",
                exerciseNames: ["Bench Press", "Easy Run"],
                exerciseModes: [.weightReps, .duration]
            ) == .traditionalStrengthTraining
        )
    }

    @Test("run title maps to running")
    func runTitle() {
        #expect(
            WatchWorkoutActivityKind.inferred(
                sessionTitle: "Easy run",
                exerciseNames: ["Treadmill"],
                exerciseModes: [.duration]
            ) == .running
        )
    }

    @Test("cycle names map to cycling")
    func cycleNames() {
        #expect(
            WatchWorkoutActivityKind.inferred(
                sessionTitle: nil,
                exerciseNames: ["Stationary bike"],
                exerciseModes: [.distanceDuration]
            ) == .cycling
        )
    }

    @Test("walk maps to walking")
    func walkTitle() {
        #expect(
            WatchWorkoutActivityKind.inferred(
                sessionTitle: "Zone 2 walk",
                exerciseNames: [],
                exerciseModes: [.duration]
            ) == .walking
        )
    }

    @Test("HIIT maps")
    func hiitTitle() {
        #expect(
            WatchWorkoutActivityKind.inferred(
                sessionTitle: "HIIT intervals",
                exerciseNames: ["Assault bike"],
                exerciseModes: [.duration]
            ) == .highIntensityIntervalTraining
        )
    }

    @Test("generic cardio maps mixed")
    func genericCardio() {
        #expect(
            WatchWorkoutActivityKind.inferred(
                sessionTitle: "Cardio",
                exerciseNames: ["Row"],
                exerciseModes: [.duration]
            ) == .mixedCardio
        )
    }
}

@Suite("WatchCompanionPushKey")
struct WatchCompanionPushKeyTests {
    @Test("floors restEndsAt so sub-second drift does not re-push")
    func floorsRest() {
        let a = WatchCompanionPushKey(active: true, restEndsAt: 100.9)
        let b = WatchCompanionPushKey(active: true, restEndsAt: 100.1)
        #expect(a == b)
    }

    @Test("set change is a new key")
    func setChange() {
        let a = WatchCompanionPushKey(active: true, setID: "s1")
        let b = WatchCompanionPushKey(active: true, setID: "s2")
        #expect(a != b)
    }
}

@Suite("WatchReadinessFaceStore")
struct WatchReadinessFaceStoreTests {
    @Test("round-trips score and band")
    func roundTrip() {
        let suite = "WatchReadinessFaceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        WatchReadinessFaceStore.save(score: 64, band: "balanced", now: 10, defaults: defaults)
        let loaded = WatchReadinessFaceStore.load(defaults: defaults)
        #expect(loaded?.score == 64)
        #expect(loaded?.band == "balanced")
        #expect(loaded?.updatedAt == 10)
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("empty defaults returns nil")
    func emptyNil() {
        let suite = "WatchReadinessFaceStoreTests.empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(WatchReadinessFaceStore.load(defaults: defaults) == nil)
        defaults.removePersistentDomain(forName: suite)
    }
}
