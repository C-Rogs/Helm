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
        var heartRateBPM: Int?
        var sessionExerciseID: String?
        var currentSetID: String?

        var isResting: Bool {
            (restRemainingSeconds ?? 0) > 0
        }
    }

    var sessionTitle: String
    var startedAt: Date
}
