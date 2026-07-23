import Core
import Foundation

public struct PostWorkoutSummary: Sendable, Equatable {
    public let setCount: Int
    public let exerciseCount: Int
    public let durationMinutes: Int
    public let personalRecordCount: Int

    public init(
        setCount: Int,
        exerciseCount: Int,
        durationMinutes: Int,
        personalRecordCount: Int
    ) {
        self.setCount = setCount
        self.exerciseCount = exerciseCount
        self.durationMinutes = durationMinutes
        self.personalRecordCount = personalRecordCount
    }
}

public enum PostWorkoutSummaryBuilder {
    public static func build(
        session: WorkoutSessionDraft,
        personalRecords: [DetectedPersonalRecord]
    ) -> PostWorkoutSummary {
        var setCount = 0
        for exercise in session.exercises {
            for set in exercise.sets where set.status == .completed && !set.setType.isWarmup {
                setCount += 1
            }
        }

        let exerciseCount = session.exercises.count
        let durationMinutes: Int
        if let endedAt = session.endedAt {
            durationMinutes = max(1, Int(endedAt.timeIntervalSince(session.startedAt) / 60))
        } else {
            durationMinutes = 1
        }

        return PostWorkoutSummary(
            setCount: setCount,
            exerciseCount: exerciseCount,
            durationMinutes: durationMinutes,
            personalRecordCount: personalRecords.count
        )
    }
}
