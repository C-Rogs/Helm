import Core
import Foundation
import PlanKit

enum MuscleVolumeRecencyBuilder {
    static func lastTrainedDays(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap]
    ) -> [MuscleGroup: HelmDay] {
        var lastTrained: [MuscleGroup: HelmDay] = [:]

        for session in sessions {
            for set in session.sets where isHardSet(set) {
                guard let map = muscleMaps[set.exerciseID] else { continue }
                for contribution in map.contributions {
                    let muscle = contribution.muscle
                    if let existing = lastTrained[muscle] {
                        if session.helmDay > existing {
                            lastTrained[muscle] = session.helmDay
                        }
                    } else {
                        lastTrained[muscle] = session.helmDay
                    }
                }
            }
        }

        return lastTrained
    }

    static func calendarDays(from start: HelmDay, to end: HelmDay, calendar: Calendar) -> Int {
        guard
            let startDate = calendar.date(from: start.dateComponents()),
            let endDate = calendar.date(from: end.dateComponents())
        else {
            return 0
        }
        let dayCount = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return max(0, dayCount)
    }

    private static func isHardSet(_ set: LoggedSet) -> Bool {
        !set.isWarmup && set.reps != nil
    }
}
