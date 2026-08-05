import Core
import Foundation

/// Fractional credit of a logged set toward a muscle.
public struct ExerciseMuscleContribution: Sendable, Hashable, Codable {
    public let muscle: MuscleGroup
    /// Share of the set credited to this muscle (0...1); contributions per exercise should sum to 1.
    public let fraction: Double
    /// Explicit ledger tier; when nil, inferred from `fraction`.
    public let tier: MuscleContributionTier?

    public init(
        muscle: MuscleGroup,
        fraction: Double,
        tier: MuscleContributionTier? = nil
    ) {
        precondition(fraction > 0 && fraction <= 1, "fraction must be in (0, 1]")
        self.muscle = muscle
        self.fraction = fraction
        self.tier = tier
    }

    /// Hard-set credit for one logged working set toward this muscle.
    public var effectiveCredit: Double {
        (tier ?? MuscleContributionTier.inferred(from: fraction)).credit
    }

    public var isDirect: Bool {
        effectiveCredit >= MuscleContributionTier.primary.credit
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

/// Per-muscle direct vs synergist volume for synergist-cap accounting.
public struct MuscleVolumeBreakdown: Sendable, Hashable, Codable {
    public let direct: Double
    public let synergist: Double

    public init(direct: Double, synergist: Double) {
        self.direct = direct
        self.synergist = synergist
    }

    /// Effective weekly volume after applying the synergist ceiling.
    public func effective(
        weeklyTarget: Int,
        synergistCapFraction: Double = 0.5
    ) -> Double {
        let cap = Double(weeklyTarget) * synergistCapFraction
        return direct + min(synergist, cap)
    }
}

enum HardSetAccounting {
    /// Indirect fractional sets may satisfy at most this share of weekly target volume.
    static let synergistWeeklyCapFraction = 0.5
    /// Drop / rest-pause slots cannot exceed this primary credit per exercise entry.
    static let intensityTechniquePrimaryCap = 1.5
    /// Drop-set portion credit toward the primary mover only.
    static let dropSetStimulusCredit = 0.5

    /// Hypertrophy stimulus multiplier for one logged set (0 = not a hard set).
    static func stimulusCredit(_ set: LoggedSet) -> Double {
        guard set.reps != nil else { return 0 }
        switch set.setType {
        case .warmup, .assisted, .timed, .distance:
            return 0
        case .dropSet:
            return dropSetStimulusCredit
        case .normal, .failure, .bodyweight:
            return 1.0
        }
    }

    static func isHardSet(_ set: LoggedSet) -> Bool {
        stimulusCredit(set) > 0
    }

    static func effectiveVolume(
        direct: Double,
        synergist: Double,
        weeklyTarget: Int,
        synergistCapFraction: Double = synergistWeeklyCapFraction
    ) -> Double {
        let cap = Double(weeklyTarget) * synergistCapFraction
        return direct + min(synergist, cap)
    }

    static func weeklyVolumeBreakdown(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        weekStart: HelmDay
    ) -> [MuscleGroup: MuscleVolumeBreakdown] {
        volumeBreakdown(
            sessions: sessions,
            muscleMaps: muscleMaps,
            on: weekDays(startingAt: weekStart)
        )
    }

    private static func volumeBreakdown(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        on days: Set<HelmDay>
    ) -> [MuscleGroup: MuscleVolumeBreakdown] {
        var direct: [MuscleGroup: Double] = [:]
        var synergist: [MuscleGroup: Double] = [:]

        for session in sessions where days.contains(session.helmDay) {
            let credited = session.sets.filter { stimulusCredit($0) > 0 }
            let byExercise = Dictionary(grouping: credited, by: \.exerciseID)

            for (exerciseID, sets) in byExercise {
                guard let map = muscleMaps[exerciseID] else { continue }
                var normalPrimary: [MuscleGroup: Double] = [:]
                var intensityPrimary: [MuscleGroup: Double] = [:]

                for set in sets {
                    let stimulus = stimulusCredit(set)
                    for contribution in map.contributions {
                        // Drop portion credits primary mover only.
                        if set.setType == .dropSet, !contribution.isDirect {
                            continue
                        }
                        let credit = contribution.effectiveCredit * stimulus
                        guard credit > 0 else { continue }
                        if contribution.isDirect {
                            if set.setType == .dropSet {
                                intensityPrimary[contribution.muscle, default: 0] += credit
                            } else {
                                normalPrimary[contribution.muscle, default: 0] += credit
                            }
                        } else {
                            synergist[contribution.muscle, default: 0] += credit
                        }
                    }
                }

                let muscles = Set(normalPrimary.keys).union(intensityPrimary.keys)
                for muscle in muscles {
                    let intensity = min(
                        intensityPrimary[muscle, default: 0],
                        intensityTechniquePrimaryCap
                    )
                    direct[muscle, default: 0] += normalPrimary[muscle, default: 0] + intensity
                }
            }
        }

        let muscles = Set(direct.keys).union(synergist.keys)
        return Dictionary(uniqueKeysWithValues: muscles.map { muscle in
            (muscle, MuscleVolumeBreakdown(
                direct: direct[muscle, default: 0],
                synergist: synergist[muscle, default: 0]
            ))
        })
    }

    /// Weekly hard sets still available for prescription after synergist-cap accounting.
    static func remainingWeeklyHardSets(
        weeklyTarget: Int,
        breakdown: MuscleVolumeBreakdown
    ) -> Double {
        max(0, Double(weeklyTarget) - breakdown.effective(weeklyTarget: weeklyTarget))
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
        let breakdown = weeklyVolumeBreakdown(
            sessions: sessions,
            muscleMaps: muscleMaps,
            weekStart: weekStart
        )
        var totals: [MuscleGroup: Double] = [:]
        for (muscle, volume) in breakdown {
            totals[muscle] = volume.direct + volume.synergist
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
        let breakdown = volumeBreakdown(
            sessions: sessions,
            muscleMaps: muscleMaps,
            on: windowDaysSet
        )
        var totals: [MuscleGroup: Double] = [:]
        for (muscle, volume) in breakdown {
            totals[muscle] = volume.direct + volume.synergist
        }

        return WeeklyHardSetLedger(weekStart: windowStart, totals: totals)
    }
}
