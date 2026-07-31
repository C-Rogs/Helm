import Core
import Foundation

/// Fractional credit of a logged set toward a muscle.
public struct ExerciseMuscleContribution: Sendable, Hashable, Codable {
    public let muscle: MuscleGroup
    /// Share of the set credited to this muscle (0...1); contributions per exercise should sum to 1.
    public let fraction: Double

    public init(muscle: MuscleGroup, fraction: Double) {
        precondition(fraction > 0 && fraction <= 1, "fraction must be in (0, 1]")
        self.muscle = muscle
        self.fraction = fraction
    }
}

/// Maps a canonical exercise to the muscles it trains.
public struct ExerciseMuscleMap: Sendable, Hashable, Codable {
    public let exerciseID: String
    public let contributions: [ExerciseMuscleContribution]

    public init(exerciseID: String, contributions: [ExerciseMuscleContribution]) {
        self.exerciseID = exerciseID
        self.contributions = contributions
    }
}

/// Per-muscle hard-set totals for a training week.
public struct WeeklyHardSetLedger: Sendable, Hashable, Codable {
    public let weekStart: HelmDay
    public let totals: [MuscleGroup: Double]

    public init(weekStart: HelmDay, totals: [MuscleGroup: Double]) {
        self.weekStart = weekStart
        self.totals = totals
    }
}

enum HardSetAccounting {
    static func isHardSet(_ set: LoggedSet) -> Bool {
        !set.isWarmup && set.reps != nil
    }

    static func rollingDays(endingAt endDay: HelmDay, count: Int = 7) -> Set<HelmDay> {
        guard count > 0 else { return [] }
        var days: Set<HelmDay> = []
        for offset in 0 ..< count {
            days.insert(endDay.adding(days: -offset))
        }
        return days
    }

    static func weekDays(startingAt weekStart: HelmDay, count: Int = 7) -> Set<HelmDay> {
        var days: Set<HelmDay> = []
        var year = weekStart.year
        var month = weekStart.month
        var day = weekStart.day
        for _ in 0 ..< count {
            days.insert(HelmDay(year: year, month: month, day: day))
            day += 1
            let daysInMonth: Int = switch month {
            case 1, 3, 5, 7, 8, 10, 12: 31
            case 4, 6, 9, 11: 30
            case 2: (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28
            default: 30
            }
            if day > daysInMonth {
                day = 1
                month += 1
                if month > 12 {
                    month = 1
                    year += 1
                }
            }
        }
        return days
    }

    static func weeklyHardSetTotals(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        weekStart: HelmDay
    ) -> WeeklyHardSetLedger {
        let weekDays = weekDays(startingAt: weekStart)
        var totals: [MuscleGroup: Double] = [:]

        for session in sessions where weekDays.contains(session.helmDay) {
            for set in session.sets where isHardSet(set) {
                guard let map = muscleMaps[set.exerciseID] else { continue }
                for contribution in map.contributions {
                    totals[contribution.muscle, default: 0] += contribution.fraction
                }
            }
        }

        return WeeklyHardSetLedger(weekStart: weekStart, totals: totals)
    }

    static func rollingHardSetTotals(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        endingAt endDay: HelmDay,
        windowDays: Int = 7
    ) -> WeeklyHardSetLedger {
        let windowStart = endDay.adding(days: -(windowDays - 1))
        let windowDaysSet = rollingDays(endingAt: endDay, count: windowDays)
        var totals: [MuscleGroup: Double] = [:]

        for session in sessions where windowDaysSet.contains(session.helmDay) {
            for set in session.sets where isHardSet(set) {
                guard let map = muscleMaps[set.exerciseID] else { continue }
                for contribution in map.contributions {
                    totals[contribution.muscle, default: 0] += contribution.fraction
                }
            }
        }

        return WeeklyHardSetLedger(weekStart: windowStart, totals: totals)
    }
}
