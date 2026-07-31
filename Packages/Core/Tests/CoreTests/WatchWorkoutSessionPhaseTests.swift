import Testing
@testable import Core

@Suite("Watch workout session state machine")
struct WatchWorkoutSessionPhaseTests {
    @Test("start path: idle → preparing → active → ending → ended")
    func startPauseEndPath() {
        var phase = WatchWorkoutSessionPhase.idle
        phase = apply(&phase, .startRequested)
        phase = apply(&phase, .sessionReady)
        phase = apply(&phase, .endRequested)
        phase = apply(&phase, .teardownSucceeded)
        #expect(phase == .ended)
    }

    @Test("pause and resume during active session")
    func pauseResumePath() {
        var phase = WatchWorkoutSessionPhase.active
        phase = apply(&phase, .pause)
        #expect(phase == .paused)
        phase = apply(&phase, .resume)
        #expect(phase == .active)
    }

    @Test("teardown failure from ending resets to idle")
    func teardownFailureResets() {
        var phase = WatchWorkoutSessionPhase.ending
        phase = apply(&phase, .teardownFailed)
        #expect(phase == .idle)
    }

    @Test("maps HealthKit strength activity raw value to Watch kind")
    func mapsStrengthActivityRawValue() {
        #expect(
            WatchWorkoutActivityKind.fromHealthKitActivityTypeRawValue(50)
                == .traditionalStrengthTraining
        )
        #expect(
            WatchWorkoutActivityKind.fromHealthKitActivityTypeRawValue(9999)
                == .traditionalStrengthTraining
        )
    }

    @Test("teardown steps preserve builder order; discard skips finish")
    func teardownStepOrder() {
        #expect(WatchWorkoutSessionReducer.teardownSteps(discard: false) == [
            .endCollection, .finishWorkout, .endSession
        ])
        #expect(WatchWorkoutSessionReducer.teardownSteps(discard: true) == [
            .endCollection, .discardWorkout, .endSession
        ])
    }

    private func apply(
        _ phase: inout WatchWorkoutSessionPhase,
        _ event: WatchWorkoutSessionEvent
    ) -> WatchWorkoutSessionPhase {
        let next = WatchWorkoutSessionReducer.reduce(phase: phase, event: event)
        #expect(next != nil)
        phase = next!
        return phase
    }
}
