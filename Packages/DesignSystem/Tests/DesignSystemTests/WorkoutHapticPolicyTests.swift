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

    @Test("Rest count-in fires once per second in final five seconds")
    func restCountInPerSecond() {
        let transitions: [(Int?, Int, Int)] = [
            (6, 5, 5),
            (5, 4, 4),
            (4, 3, 3),
            (3, 2, 2),
            (2, 1, 1)
        ]

        var state = RestTimerHapticPolicy.State()
        for (previous, current, expectedSecond) in transitions {
            let evaluation = RestTimerHapticPolicy.evaluateForegroundTransition(
                timerID: "timer-1",
                previousRemaining: previous,
                currentRemaining: current,
                state: state
            )
            #expect(evaluation.patterns == [.restCountInStep(remainingSeconds: expectedSecond)])
            #expect(evaluation.markCountInPlayedSecond == expectedSecond)
            state.apply(evaluation)
        }
    }

    @Test("Rest count-in does not repeat the same second")
    func restCountInDedupedPerSecond() {
        var state = RestTimerHapticPolicy.State()
        let first = RestTimerHapticPolicy.evaluateForegroundTransition(
            timerID: "timer-1",
            previousRemaining: 6,
            currentRemaining: 5,
            state: state
        )
        state.apply(first)

        let repeatTick = RestTimerHapticPolicy.evaluateForegroundTransition(
            timerID: "timer-1",
            previousRemaining: 6,
            currentRemaining: 5,
            state: state
        )
        #expect(repeatTick.patterns.isEmpty)
    }

    @Test("Rest count-in does not fire above threshold")
    func restCountInAboveThreshold() {
        let evaluation = RestTimerHapticPolicy.evaluateForegroundTransition(
            timerID: "timer-1",
            previousRemaining: 7,
            currentRemaining: 6,
            state: .init()
        )
        #expect(evaluation.patterns.isEmpty)
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
