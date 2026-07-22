import Testing
@testable import DesignSystem

@Suite("Workout haptic policy")
struct WorkoutHapticPolicyTests {
    @Test("Set completion skips already completed rows")
    func setCompletionSkipsCompleted() {
        #expect(SetCompletionHapticPolicy.pattern(wasAlreadyCompleted: true) == nil)
        #expect(SetCompletionHapticPolicy.pattern(wasAlreadyCompleted: false) == .setLogged)
    }

    @Test("PR haptic fires once per qualifying record key")
    func personalRecordOncePerKey() {
        let key = PersonalRecordHapticPolicy.stableKey(exerciseID: "bench", metricType: "maxWeight")
        let played: Set<String> = [key]
        #expect(
            PersonalRecordHapticPolicy.newRecordKeys(recordKeys: [key], alreadyPlayed: played).isEmpty
        )
        #expect(
            PersonalRecordHapticPolicy.newRecordKeys(
                recordKeys: [key, "squat|estimatedOneRM"],
                alreadyPlayed: played
            ) == ["squat|estimatedOneRM"]
        )
    }

    @Test("Rest count-in fires entering final seconds")
    func restCountInThreshold() {
        let evaluation = RestTimerHapticPolicy.evaluateForegroundTransition(
            timerID: "timer-1",
            previousRemaining: 4,
            currentRemaining: 3,
            state: .init()
        )
        #expect(evaluation.patterns == [.restCountIn])
        #expect(evaluation.markCountInPlayed)
    }

    @Test("Rest done fires when countdown reaches zero")
    func restDoneAtZero() {
        let evaluation = RestTimerHapticPolicy.evaluateForegroundTransition(
            timerID: "timer-1",
            previousRemaining: 1,
            currentRemaining: 0,
            state: .init()
        )
        #expect(evaluation.patterns == [.restDone])
        #expect(evaluation.markRestDonePlayed)
    }

    @Test("Rest done does not repeat for the same timer")
    func restDoneDeduped() {
        var state = RestTimerHapticPolicy.State()
        state.restDonePlayedForTimerIDs.insert("timer-1")

        let evaluation = RestTimerHapticPolicy.evaluateForegroundTransition(
            timerID: "timer-1",
            previousRemaining: 1,
            currentRemaining: 0,
            state: state
        )
        #expect(evaluation.patterns.isEmpty)
    }

    @Test("Foreground return after background rest completion")
    func restDoneOnForegroundReturn() {
        let evaluation = RestTimerHapticPolicy.evaluateForegroundReturn(
            timerID: "timer-1",
            wasRunningOnBackground: true,
            currentRemaining: nil,
            state: .init()
        )
        #expect(evaluation.patterns == [.restDone])
    }

    @Test("Notification delivery maps to rest done")
    func restDoneFromNotification() {
        let evaluation = RestTimerHapticPolicy.evaluateNotificationDelivery(
            categoryIdentifier: "helm.rest_timer",
            restCategoryID: "helm.rest_timer",
            timerID: "timer-1",
            state: .init()
        )
        #expect(evaluation.patterns == [.restDone])
    }
}
