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
    public static let countInThresholdSeconds = 3

    public struct Evaluation: Equatable, Sendable {
        public let patterns: [HelmHaptic]
        public let timerID: String?
        public let markCountInPlayed: Bool
        public let markRestDonePlayed: Bool

        public init(
            patterns: [HelmHaptic],
            timerID: String? = nil,
            markCountInPlayed: Bool = false,
            markRestDonePlayed: Bool = false
        ) {
            self.patterns = patterns
            self.timerID = timerID
            self.markCountInPlayed = markCountInPlayed
            self.markRestDonePlayed = markRestDonePlayed
        }
    }

    public struct State: Equatable, Sendable {
        public var countInPlayedForTimerID: String?
        public var restDonePlayedForTimerIDs: Set<String>

        public init(
            countInPlayedForTimerID: String? = nil,
            restDonePlayedForTimerIDs: Set<String> = []
        ) {
            self.countInPlayedForTimerID = countInPlayedForTimerID
            self.restDonePlayedForTimerIDs = restDonePlayedForTimerIDs
        }

        public mutating func apply(_ evaluation: Evaluation) {
            if evaluation.markCountInPlayed, let timerID = evaluation.timerID {
                countInPlayedForTimerID = timerID
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
        var markCountIn = false
        var markRestDone = false

        if let current = currentRemaining,
           current > 0,
           current <= countInThresholdSeconds,
           state.countInPlayedForTimerID != timerID {
            patterns.append(.restCountIn)
            markCountIn = true
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
            markCountInPlayed: markCountIn,
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
