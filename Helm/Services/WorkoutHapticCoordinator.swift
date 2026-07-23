import Core
import DesignSystem
import Foundation
import Persistence

@MainActor
enum WorkoutHapticCoordinator {
    static var restState = RestTimerHapticPolicy.State()
    static var playedPersonalRecordKeys: Set<String> = []

    static func resetRestState() {
        restState = RestTimerHapticPolicy.State()
    }

    static func play(_ pattern: HelmHaptic) {
        HapticEngine.shared.play(pattern)
    }

    static func playCoachAdjustment() {
        play(.coachAdjust)
    }

    static func playSessionFinished() {
        play(.sessionFinished)
    }

    static func playSetCompletion(wasAlreadyCompleted: Bool) {
        guard let pattern = SetCompletionHapticPolicy.pattern(wasAlreadyCompleted: wasAlreadyCompleted) else {
            return
        }
        play(pattern)
    }

    static func playPersonalRecords(_ records: [DetectedPersonalRecord]) {
        let keys = records.map {
            PersonalRecordHapticPolicy.stableKey(
                exerciseID: $0.exerciseID,
                metricType: $0.metricType.rawValue
            )
        }
        let newKeys = PersonalRecordHapticPolicy.newRecordKeys(
            recordKeys: keys,
            alreadyPlayed: playedPersonalRecordKeys
        )
        guard !newKeys.isEmpty else { return }
        playedPersonalRecordKeys.formUnion(newKeys)
        play(.prHit)
    }

    static func applyRestEvaluation(_ evaluation: RestTimerHapticPolicy.Evaluation) {
        restState.apply(evaluation)
        for pattern in evaluation.patterns {
            play(pattern)
        }
    }

    static func handleForegroundTransition(
        timerID: String?,
        previousRemaining: Int?,
        currentRemaining: Int?
    ) {
        let evaluation = RestTimerHapticPolicy.evaluateForegroundTransition(
            timerID: timerID,
            previousRemaining: previousRemaining,
            currentRemaining: currentRemaining,
            state: restState
        )
        applyRestEvaluation(evaluation)
    }

    static func handleForegroundReturn(
        timerID: String?,
        wasRunningOnBackground: Bool,
        currentRemaining: Int?
    ) {
        let evaluation = RestTimerHapticPolicy.evaluateForegroundReturn(
            timerID: timerID,
            wasRunningOnBackground: wasRunningOnBackground,
            currentRemaining: currentRemaining,
            state: restState
        )
        applyRestEvaluation(evaluation)
    }

    static func handleRestNotification(
        categoryIdentifier: String,
        timerID: String?
    ) {
        let evaluation = RestTimerHapticPolicy.evaluateNotificationDelivery(
            categoryIdentifier: categoryIdentifier,
            restCategoryID: RestTimerNotificationPlanner.notificationCategoryID,
            timerID: timerID,
            state: restState
        )
        applyRestEvaluation(evaluation)
    }
}
