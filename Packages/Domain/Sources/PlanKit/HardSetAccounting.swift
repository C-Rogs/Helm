import Core
import Foundation

/// Reference 1RM per exercise, used for the warmup load floor.
public struct HardSetEvaluationContext: Sendable, Hashable, Codable {
    public let estimatedOneRepMaxByExercise: [String: Mass]

    public init(estimatedOneRepMaxByExercise: [String: Mass] = [:]) {
        self.estimatedOneRepMaxByExercise = estimatedOneRepMaxByExercise
    }

    public static let empty = HardSetEvaluationContext()
}

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
    /// Stimulus totals, compared against the weekly target and MEV.
    public let totals: [MuscleGroup: Double]
    /// Fatigue totals, compared against MRV.
    public let fatigueTotals: [MuscleGroup: Double]

    public init(
        weekStart: HelmDay,
        totals: [MuscleGroup: Double],
        fatigueTotals: [MuscleGroup: Double] = [:]
    ) {
        self.weekStart = weekStart
        self.totals = totals
        self.fatigueTotals = fatigueTotals
    }
}

/// Per-muscle direct vs synergist volume for synergist-cap accounting.
public struct MuscleVolumeBreakdown: Sendable, Hashable, Codable {
    public let direct: Double
    public let synergist: Double
    /// Recovery cost accrued for this muscle. Unlike stimulus, fatigue does not saturate.
    public let fatigue: Double

    public init(direct: Double, synergist: Double, fatigue: Double = 0) {
        self.direct = direct
        self.synergist = synergist
        self.fatigue = fatigue
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
    static let synergistWeeklyCapFraction = HardSetPolicy.standard.synergistWeeklyCapFraction
    static let intensityTechniquePrimaryCap = HardSetPolicy.standard.intensityTechniquePrimaryCap

    // MARK: - Per-set credit

    /// Stimulus and fatigue for one logged set.
    static func ledgerCredit(
        _ set: LoggedSet,
        role: SetStimulusRole,
        context: HardSetEvaluationContext = .empty,
        policy: HardSetPolicy = .standard
    ) -> SetLedgerCredit {
        guard let reps = set.reps, reps > 0, role != .excluded else { return .none }

        let rir = claimedRIR(set)
        let proximity = policy.proximityCredit(rir: rir)
        guard proximity > 0 else { return .none }
        let fatigue = policy.fatigueCost(rpe: effectiveRPE(set, rir: rir))

        switch role {
        case .excluded:
            return .none
        case .intensityExtension:
            // Rep and load bands describe self-contained working sets. A rest-pause mini-set
            // of 4 reps is not "too few reps to count", it is the tail of a set that already
            // qualified, so grading it in isolation would zero legitimate work.
            let base = set.setType == .dropSet ? policy.dropSetCredit : policy.restPauseFollowUpCredit
            return SetLedgerCredit(stimulus: base * proximity, fatigue: fatigue)
        case .topWorking:
            guard clearsLoadFloor(set, context: context, policy: policy) else { return .none }
            return SetLedgerCredit(
                stimulus: policy.repBandCredit(reps: reps) * proximity,
                fatigue: fatigue
            )
        }
    }

    /// Hypertrophy stimulus multiplier for one logged set (0 = not a hard set).
    static func stimulusCredit(
        _ set: LoggedSet,
        context: HardSetEvaluationContext = .empty,
        policy: HardSetPolicy = .standard
    ) -> Double {
        ledgerCredit(set, role: SetStimulusRole(set.setType), context: context, policy: policy).stimulus
    }

    static func isHardSet(
        _ set: LoggedSet,
        context: HardSetEvaluationContext = .empty
    ) -> Bool {
        stimulusCredit(set, context: context) > 0
    }

    /// True when a drop-set row has no preceding top working set in the same exercise.
    static func isOrphanDropSet(_ set: LoggedSet, priorSetsInExercise: [LoggedSet]) -> Bool {
        guard set.setType == .dropSet else { return false }
        return !priorSetsInExercise.contains { prior in
            prior.sequence < set.sequence && SetStimulusRole(prior.setType) == .topWorking
        }
    }

    static func buildEvaluationContext(from sessions: [WorkoutSession]) -> HardSetEvaluationContext {
        var accumulator = LoadReferenceAccumulator()
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        for session in ordered {
            accumulator.ingest(session)
        }
        let asOf = ordered.last?.startedAt ?? Date()
        return accumulator.context(asOf: asOf)
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

    /// Weekly hard sets still available for prescription.
    ///
    /// When an MRV ceiling is supplied the athlete is held to whichever runs out first:
    /// stimulus headroom against the weekly target, or recovery headroom against MRV.
    static func remainingWeeklyHardSets(
        weeklyTarget: Int,
        breakdown: MuscleVolumeBreakdown,
        fatigueCeiling: Int? = nil,
        policy: HardSetPolicy = .standard
    ) -> Double {
        let accrued = breakdown.effective(
            weeklyTarget: weeklyTarget,
            synergistCapFraction: policy.synergistWeeklyCapFraction
        )
        let stimulusHeadroom = max(0, Double(weeklyTarget) - accrued)
        guard let fatigueCeiling else { return stimulusHeadroom }
        let fatigueHeadroom = max(0, Double(fatigueCeiling) - breakdown.fatigue)
        return min(stimulusHeadroom, fatigueHeadroom)
    }

    // MARK: - Aggregation

    static func weeklyVolumeBreakdown(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        weekStart: HelmDay,
        context: HardSetEvaluationContext? = nil,
        policy: HardSetPolicy = .standard
    ) -> [MuscleGroup: MuscleVolumeBreakdown] {
        volumeBreakdown(
            sessions: sessions,
            muscleMaps: muscleMaps,
            on: weekDays(startingAt: weekStart),
            context: context,
            policy: policy
        )
    }

    static func weeklyHardSetTotals(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        weekStart: HelmDay,
        context: HardSetEvaluationContext? = nil,
        policy: HardSetPolicy = .standard
    ) -> WeeklyHardSetLedger {
        let breakdown = weeklyVolumeBreakdown(
            sessions: sessions,
            muscleMaps: muscleMaps,
            weekStart: weekStart,
            context: context,
            policy: policy
        )
        return ledger(weekStart: weekStart, breakdown: breakdown)
    }

    static func rollingHardSetTotals(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        endingAt endDay: HelmDay,
        windowDays: Int = 7,
        context: HardSetEvaluationContext? = nil,
        policy: HardSetPolicy = .standard
    ) -> WeeklyHardSetLedger {
        let windowStart = endDay.adding(days: -(windowDays - 1))
        let breakdown = volumeBreakdown(
            sessions: sessions,
            muscleMaps: muscleMaps,
            on: rollingDays(endingAt: endDay, count: windowDays),
            context: context,
            policy: policy
        )
        return ledger(weekStart: windowStart, breakdown: breakdown)
    }

    private static func ledger(
        weekStart: HelmDay,
        breakdown: [MuscleGroup: MuscleVolumeBreakdown]
    ) -> WeeklyHardSetLedger {
        var totals: [MuscleGroup: Double] = [:]
        var fatigueTotals: [MuscleGroup: Double] = [:]
        for (muscle, volume) in breakdown {
            totals[muscle] = volume.direct + volume.synergist
            fatigueTotals[muscle] = volume.fatigue
        }
        return WeeklyHardSetLedger(weekStart: weekStart, totals: totals, fatigueTotals: fatigueTotals)
    }

    /// Single chronological pass: reference 1RM is folded forward, never read from the future.
    private static func volumeBreakdown(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        on days: Set<HelmDay>,
        context: HardSetEvaluationContext?,
        policy: HardSetPolicy
    ) -> [MuscleGroup: MuscleVolumeBreakdown] {
        var totals = LedgerTotals()
        var reference = LoadReferenceAccumulator(policy: policy)
        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }

        for session in ordered {
            defer { reference.ingest(session) }
            guard days.contains(session.helmDay) else { continue }
            let sessionContext = context ?? reference.context(asOf: session.startedAt)
            let accrued = sessionVolume(
                session: session,
                muscleMaps: muscleMaps,
                context: sessionContext,
                policy: policy
            )
            totals.merge(accrued, saturation: policy.sessionSaturation)
        }

        return totals.breakdowns()
    }

    private static func sessionVolume(
        session: WorkoutSession,
        muscleMaps: [String: ExerciseMuscleMap],
        context: HardSetEvaluationContext,
        policy: HardSetPolicy
    ) -> LedgerTotals {
        var totals = LedgerTotals()
        let byExercise = Dictionary(grouping: session.sets, by: \.exerciseID)
        for (exerciseID, sets) in byExercise {
            guard let map = muscleMaps[exerciseID] else { continue }
            let accumulator = exerciseVolume(
                sets: sets.sorted { $0.sequence < $1.sequence },
                map: map,
                context: context,
                policy: policy
            )
            accumulator.flush(into: &totals, policy: policy)
        }
        return totals
    }

    private static func exerciseVolume(
        sets: [LoggedSet],
        map: ExerciseMuscleMap,
        context: HardSetEvaluationContext,
        policy: HardSetPolicy
    ) -> ExerciseAccumulator {
        var accumulator = ExerciseAccumulator()
        var sawTopWorking = false

        for set in sets {
            let declared = SetStimulusRole(set.setType)
            // A lone drop row is the working set the athlete forgot to log as one.
            let orphanDrop = declared == .intensityExtension
                && set.setType == .dropSet
                && !sawTopWorking
            let role: SetStimulusRole = orphanDrop ? .topWorking : declared
            if role == .topWorking { sawTopWorking = true }

            let credit = ledgerCredit(set, role: role, context: context, policy: policy)
            guard credit.isCredited else { continue }
            accumulator.add(credit, role: role, setType: set.setType, map: map)
        }
        return accumulator
    }

    // MARK: - Day windows

    static func rollingDays(endingAt endDay: HelmDay, count: Int = 7) -> Set<HelmDay> {
        guard count > 0 else { return [] }
        var days: Set<HelmDay> = []
        for offset in 0 ..< count {
            days.insert(endDay.adding(days: -offset))
        }
        return days
    }

    static func weekDays(startingAt weekStart: HelmDay, count: Int = 7) -> Set<HelmDay> {
        guard count > 0 else { return [] }
        var days: Set<HelmDay> = []
        for offset in 0 ..< count {
            days.insert(weekStart.adding(days: offset))
        }
        return days
    }

    // MARK: - Gates

    private static func claimedRIR(_ set: LoggedSet) -> Double? {
        if let rir = set.rir { return Double(rir) }
        if let rpe = set.rpe { return max(0, 10 - rpe) }
        return nil
    }

    private static func effectiveRPE(_ set: LoggedSet, rir: Double?) -> Double? {
        if let rpe = set.rpe { return rpe }
        if let rir { return 10 - rir }
        return nil
    }

    private static func clearsLoadFloor(
        _ set: LoggedSet,
        context: HardSetEvaluationContext,
        policy: HardSetPolicy
    ) -> Bool {
        guard let mass = set.mass?.kilograms, mass > 0 else { return true }
        guard let reference = context.estimatedOneRepMaxByExercise[set.exerciseID]?.kilograms,
              reference > 0
        else { return true }
        // Floor only. There is no upper load bound: a heavy single is a real, if less
        // hypertrophically efficient, stimulus and the rep band already discounts it.
        return mass / reference >= policy.minLoadFractionOf1RM
    }
}

// MARK: - Accumulators

/// Per-muscle running totals for a window.
private struct LedgerTotals {
    var direct: [MuscleGroup: Double] = [:]
    var synergist: [MuscleGroup: Double] = [:]
    var fatigue: [MuscleGroup: Double] = [:]

    /// Fold one session in, discounting its stimulus for within-session saturation.
    ///
    /// Saturation is applied to the session total rather than set by set so the result does
    /// not depend on the order sets were logged in.
    mutating func merge(_ session: LedgerTotals, saturation: SessionSaturation) {
        for (muscle, value) in session.fatigue {
            fatigue[muscle, default: 0] += value
        }
        let muscles = Set(session.direct.keys).union(session.synergist.keys)
        for muscle in muscles {
            let sessionDirect = session.direct[muscle, default: 0]
            let sessionSynergist = session.synergist[muscle, default: 0]
            let raw = sessionDirect + sessionSynergist
            guard raw > 0 else { continue }
            let scale = saturation.effective(raw) / raw
            direct[muscle, default: 0] += sessionDirect * scale
            synergist[muscle, default: 0] += sessionSynergist * scale
        }
    }

    func breakdowns() -> [MuscleGroup: MuscleVolumeBreakdown] {
        let muscles = Set(direct.keys).union(synergist.keys).union(fatigue.keys)
        return Dictionary(uniqueKeysWithValues: muscles.map { muscle in
            (muscle, MuscleVolumeBreakdown(
                direct: direct[muscle, default: 0],
                synergist: synergist[muscle, default: 0],
                fatigue: fatigue[muscle, default: 0]
            ))
        })
    }
}

/// Buckets one exercise's credit so the intensity-technique caps can be applied per muscle.
private struct ExerciseAccumulator {
    var topWorking: [MuscleGroup: Double] = [:]
    var dropped: [MuscleGroup: Double] = [:]
    var restPause: [MuscleGroup: Double] = [:]
    var synergist: [MuscleGroup: Double] = [:]
    var fatigue: [MuscleGroup: Double] = [:]

    mutating func add(
        _ credit: SetLedgerCredit,
        role: SetStimulusRole,
        setType: SetType,
        map: ExerciseMuscleMap
    ) {
        for contribution in map.contributions {
            // Intensity extensions credit the primary mover only; synergists are not
            // meaningfully re-loaded by a drop or a rest-pause burst.
            if role == .intensityExtension, !contribution.isDirect { continue }
            let share = contribution.effectiveCredit
            guard share > 0 else { continue }

            fatigue[contribution.muscle, default: 0] += share * credit.fatigue
            let stimulus = share * credit.stimulus
            guard stimulus > 0 else { continue }

            guard contribution.isDirect else {
                synergist[contribution.muscle, default: 0] += stimulus
                continue
            }
            switch (role, setType) {
            case (.intensityExtension, .restPauseFollowUp):
                restPause[contribution.muscle, default: 0] += stimulus
            case (.intensityExtension, _):
                dropped[contribution.muscle, default: 0] += stimulus
            default:
                topWorking[contribution.muscle, default: 0] += stimulus
            }
        }
    }

    func flush(into totals: inout LedgerTotals, policy: HardSetPolicy) {
        for (muscle, value) in fatigue {
            totals.fatigue[muscle, default: 0] += value
        }
        for (muscle, value) in synergist {
            totals.synergist[muscle, default: 0] += value
        }
        let muscles = Set(topWorking.keys).union(dropped.keys).union(restPause.keys)
        for muscle in muscles {
            // Every mini-set after the activation set aggregates into a single credit.
            let aggregatedRestPause = min(restPause[muscle, default: 0], policy.restPauseAggregateCap)
            let intensity = min(
                dropped[muscle, default: 0] + aggregatedRestPause,
                policy.intensityTechniquePrimaryCap
            )
            totals.direct[muscle, default: 0] += topWorking[muscle, default: 0] + intensity
        }
    }
}
