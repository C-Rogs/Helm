import Foundation

public enum SetCompletionHapticPolicy {
    public static func pattern(wasAlreadyCompleted: Bool) -> HelmHaptic? {
        wasAlreadyCompleted ? nil : .setLogged
    }
}

public enum PersonalRecordHapticPolicy {
    public static func stableKey(exerciseID: String, metricType: String) -> String {
        "\(exerciseID)|\(metricType)"
    }

    public static func newRecordKeys(
        recordKeys: [String],
        alreadyPlayed: Set<String>
    ) -> [String] {
        recordKeys.filter { !alreadyPlayed.contains($0) }
    }
}

public enum RestTimerHapticPolicy {
    public static let countInThresholdSeconds = 5

    public struct Evaluation: Equatable, Sendable {
        public let patterns: [HelmHaptic]
        public let timerID: String?
        public let markCountInPlayedSecond: Int?
        public let markRestDonePlayed: Bool

        public init(
            patterns: [HelmHaptic],
            timerID: String? = nil,
            markCountInPlayedSecond: Int? = nil,
            markRestDonePlayed: Bool = false
        ) {
            self.patterns = patterns
            self.timerID = timerID
            self.markCountInPlayedSecond = markCountInPlayedSecond
            self.markRestDonePlayed = markRestDonePlayed
        }
    }

    public struct State: Equatable, Sendable {
        public var countInPlayedSecondsByTimer: [String: Set<Int>]
        public var restDonePlayedForTimerIDs: Set<String>

        public init(
            countInPlayedSecondsByTimer: [String: Set<Int>] = [:],
            restDonePlayedForTimerIDs: Set<String> = []
        ) {
            self.countInPlayedSecondsByTimer = countInPlayedSecondsByTimer
            self.restDonePlayedForTimerIDs = restDonePlayedForTimerIDs
        }

        public mutating func apply(_ evaluation: Evaluation) {
            if let timerID = evaluation.timerID,
               let second = evaluation.markCountInPlayedSecond {
                var played = countInPlayedSecondsByTimer[timerID] ?? []
                played.insert(second)
                countInPlayedSecondsByTimer[timerID] = played
            }
            if evaluation.markRestDonePlayed, let timerID = evaluation.timerID {
                restDonePlayedForTimerIDs.insert(timerID)
            }
        }
    }

    public static func evaluateForegroundTransition(
        timerID: String?,
        previousRemaining: Int?,
        currentRemaining: Int?,
        state: State
    ) -> Evaluation {
        guard let timerID else { return Evaluation(patterns: []) }

        var patterns: [HelmHaptic] = []
        var markCountInSecond: Int?
        var markRestDone = false

        if let current = currentRemaining,
           current > 0,
           current <= countInThresholdSeconds {
            let played = state.countInPlayedSecondsByTimer[timerID] ?? []
            if !played.contains(current) {
                patterns.append(.restCountInStep(remainingSeconds: current))
                markCountInSecond = current
            }
        }

        if let previous = previousRemaining,
           previous > 0,
           currentRemaining == 0,
           !state.restDonePlayedForTimerIDs.contains(timerID) {
            patterns.append(.restDone)
            markRestDone = true
        }

        return Evaluation(
            patterns: patterns,
            timerID: timerID,
            markCountInPlayedSecond: markCountInSecond,
            markRestDonePlayed: markRestDone
        )
    }

    public static func evaluateForegroundReturn(
        timerID: String?,
        wasRunningOnBackground: Bool,
        currentRemaining: Int?,
        state: State
    ) -> Evaluation {
        guard let timerID,
              wasRunningOnBackground,
              currentRemaining == nil,
              !state.restDonePlayedForTimerIDs.contains(timerID) else {
            return Evaluation(patterns: [])
        }
        return Evaluation(
            patterns: [.restDone],
            timerID: timerID,
            markRestDonePlayed: true
        )
    }

    public static func evaluateNotificationDelivery(
        categoryIdentifier: String,
        restCategoryID: String,
        timerID: String?,
        state: State
    ) -> Evaluation {
        guard categoryIdentifier == restCategoryID,
              let timerID,
              !state.restDonePlayedForTimerIDs.contains(timerID) else {
            return Evaluation(patterns: [])
        }
        return Evaluation(
            patterns: [.restDone],
            timerID: timerID,
            markRestDonePlayed: true
        )
    }
}
