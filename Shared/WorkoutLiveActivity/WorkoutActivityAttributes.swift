import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var currentExerciseName: String?
        var currentSetNumber: Int?
        var currentSetCount: Int?
        var targetSummary: String?
        var restRemainingSeconds: Int?
        /// When set, widgets use Text(timerInterval:) for live countdown without 1Hz updates.
        var restEndsAt: Date?
        var heartRateBPM: Int?
        var sessionExerciseID: String?
        var currentSetID: String?

        var isResting: Bool {
            if let restEndsAt {
                return restEndsAt > Date()
            }
            return (restRemainingSeconds ?? 0) > 0
        }
    }

    var sessionTitle: String
    var startedAt: Date
}
