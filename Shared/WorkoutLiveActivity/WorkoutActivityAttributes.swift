import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var currentExerciseName: String?
        var restRemainingSeconds: Int?
    }

    var sessionTitle: String
    var startedAt: Date
}
