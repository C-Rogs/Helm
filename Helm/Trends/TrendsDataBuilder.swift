import Core
import DesignSystem
import Foundation
import HealthKitIngest
import NutritionKit
import Persistence
import PlanKit
import ReadinessKit

enum TrendsDataBuilder {
    static let pageSize = 30
    static let sessionPageSize = 25
    static let recencyLookbackDays = 120
    static let defaultExerciseID = "exercise-squat"

    static func buildTrendWeightPage(
        store: PersistenceStore,
        endingAt endDay: HelmDay,
        offset: Int,
        targetWeightKg: Double?,
        calendar: Calendar = .current
    ) throws -> (bodyWeight: [TrendWeightPoint], trendWeight: [TrendWeightPoint], canLoadMore: Bool) {
        let samples = try store.bodyComposition.fetchDailyWeights(
            endingAt: endDay,
            limit: pageSize,
            offset: offset
        )
        guard !samples.isEmpty else {
            return ([], [], false)
        }

        let chronological = samples.reversed()
        let rawMasses = chronological.map(\.1)
        let filteredMasses = TrendWeightSmoother.filteredSeries(rawMasses)
        var smoothed: Double?
        let alpha = TrendWeightSmoother.alpha
        var bodyWeight: [TrendWeightPoint] = []
        var trendWeight: [TrendWeightPoint] = []

        for (index, (day, massKg)) in chronological.enumerated() {
            let rawState = trendWeightState(trendKg: massKg, targetKg: targetWeightKg)
            bodyWeight.append(TrendWeightPoint(helmDay: day, trendWeightKg: massKg, state: rawState))

            let filteredKg = filteredMasses[index]
            if let previous = smoothed {
                smoothed = alpha * filteredKg + (1 - alpha) * previous
            } else {
                smoothed = filteredKg
            }
            guard let trend = smoothed else { continue }
            let trendState = trendWeightState(trendKg: trend, targetKg: targetWeightKg)
            trendWeight.append(TrendWeightPoint(helmDay: day, trendWeightKg: trend, state: trendState))
        }

        return (bodyWeight, trendWeight, samples.count == pageSize)
    }

    static func buildReadinessPage(
        store: PersistenceStore,
        endingAt endDay: HelmDay,
        offset: Int,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> (points: [ReadinessHistoryPoint], canLoadMore: Bool) {
        let rows = try store.readiness.fetchScores(endingAt: endDay, limit: pageSize, offset: offset)
        let points = rows.compactMap { day, json -> ReadinessHistoryPoint? in
            guard let data = json.data(using: .utf8),
                  let score = try? decoder.decode(ReadinessScore.self, from: data) else {
                return nil
            }
            return ReadinessHistoryPoint(
                helmDay: day,
                score: score.score,
                state: HelmState.readiness(score: Double(score.score))
            )
        }
        .sorted { $0.helmDay < $1.helmDay }

        return (points, rows.count == pageSize)
    }

    static func buildMuscleVolume(
        store: PersistenceStore,
        weekContaining day: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> [MuscleVolumeGauge] {
        try buildMuscleVolumeRows(
            store: store,
            weekContaining: day,
            calendar: calendar,
            cutoff: cutoff
        )
        .map {
            MuscleVolumeGauge(
                muscle: $0.muscle,
                weeklySets: $0.weeklySets,
                scheduledSets: $0.scheduledSets,
                landmarks: $0.landmarks,
                state: $0.state,
                daysSinceTrained: $0.daysSinceTrained
            )
        }
    }

    static func buildMuscleVolumeBoard(
        store: PersistenceStore,
        weekContaining day: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> MuscleVolumeBoardModel {
        let rows = try buildMuscleVolumeRows(
            store: store,
            weekContaining: day,
            calendar: calendar,
            cutoff: cutoff
        )
        return MuscleVolumeBoardModel(
            rows: rows.map {
                MuscleVolumeBoardRow(
                    id: $0.muscle.rawValue,
                    label: TrendsChartSupport.muscleLabel($0.muscle),
                    weeklySets: $0.weeklySets,
                    scheduledSets: $0.scheduledSets,
                    mev: $0.landmarks.mev,
                    mrv: $0.landmarks.mrv,
                    state: $0.state,
                    daysSinceTrained: $0.daysSinceTrained
                )
            }
        )
    }

    struct MuscleVolumeRowData: Sendable {
        let muscle: MuscleGroup
        let weeklySets: Double
        let scheduledSets: Double
        let landmarks: VolumeLandmarks
        let state: HelmState
        let daysSinceTrained: Int?
    }

    static func buildMuscleVolumeRows(
        store: PersistenceStore,
        weekContaining day: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> [MuscleVolumeRowData] {
        let windowStart = day.adding(days: -(MuscleVolumeBoardModel.loadWindowDays - 1), calendar: calendar)
        let recencyStart = day.adding(days: -recencyLookbackDays, calendar: calendar)
        let windowSessions = try loadSessionsForSummary(
            store: store,
            since: windowStart,
            calendar: calendar,
            cutoff: cutoff
        )
        let recencySessions = try loadSessionsForSummary(
            store: store,
            since: recencyStart,
            calendar: calendar,
            cutoff: cutoff
        )
        let muscleMaps = try muscleMaps(from: store)
        let ledger = PlanKit.rollingHardSetTotals(
            sessions: windowSessions,
            muscleMaps: muscleMaps,
            endingAt: day,
            windowDays: MuscleVolumeBoardModel.loadWindowDays
        )
        let lastTrained = MuscleVolumeRecencyBuilder.lastTrainedDays(
            sessions: recencySessions,
            muscleMaps: muscleMaps
        )

        let mesocycle = try loadMesocycleState(from: store)
        let settings = try store.trainingPlan.load()
        let experience = TrainingExperience(rawValue: settings.experienceRaw) ?? .intermediate
        let scheduledByMuscle = try scheduledSetsByMuscle(
            store: store,
            day: day,
            logged: ledger.totals,
            mesocycle: mesocycle,
            muscleMaps: muscleMaps,
            emphasis: settings.phaseGoal.emphasis,
            calendar: calendar,
            cutoff: cutoff
        )

        return MuscleGroup.allCases.compactMap { muscle in
            let weeklySets = ledger.totals[muscle, default: 0]
            let scheduledSets = scheduledByMuscle[muscle, default: 0]
            let landmarks = mesocycle?.muscles[muscle]?.landmarks
                ?? PlanKit.seedLandmarks(muscle: muscle, experience: experience)
            guard weeklySets > 0 || scheduledSets > 0 || mesocycle?.muscles[muscle] != nil else { return nil }
            let daysSinceTrained = lastTrained[muscle].map {
                MuscleVolumeRecencyBuilder.calendarDays(from: $0, to: day, calendar: calendar)
            }
            let projected = weeklySets + scheduledSets
            return MuscleVolumeRowData(
                muscle: muscle,
                weeklySets: weeklySets,
                scheduledSets: scheduledSets,
                landmarks: landmarks,
                state: HelmState.volumeWeekly(
                    sets: projected,
                    mev: landmarks.mev,
                    mrv: landmarks.mrv
                ),
                daysSinceTrained: daysSinceTrained
            )
        }
        .sorted { ($0.weeklySets + $0.scheduledSets) > ($1.weeklySets + $1.scheduledSets) }
    }

    private static func scheduledSetsByMuscle(
        store: PersistenceStore,
        day: HelmDay,
        logged: [MuscleGroup: Double],
        mesocycle: MesocycleState?,
        muscleMaps: [String: ExerciseMuscleMap],
        emphasis: String?,
        calendar: Calendar,
        cutoff: DayCutoff
    ) throws -> [MuscleGroup: Double] {
        guard let mesocycle else { return [:] }

        let history = try PrescriptionHistoryBuilder.history(
            from: store,
            endingAt: day,
            calendar: calendar,
            cutoff: cutoff
        )
        let completedThisWeek = PrescriptionHistoryBuilder.completedSessionsThisWeek(
            in: history,
            through: day
        )
        // Trends must allow zero remaining; prescription clamp (max 1) would invent phantom volume.
        let plannedPerWeek = 3
        let remainingByPlan = max(0, plannedPerWeek - completedThisWeek)
        guard remainingByPlan > 0 else { return [:] }

        let weekEnd = history.weekStart.adding(days: 6, calendar: calendar)
        guard day <= weekEnd else { return [:] }
        var calendarSlotsLeft = 0
        var cursor = day
        while cursor <= weekEnd {
            calendarSlotsLeft += 1
            cursor = cursor.adding(days: 1, calendar: calendar)
        }
        let remainingSessions = min(remainingByPlan, calendarSlotsLeft)
        guard remainingSessions > 0 else { return [:] }

        let upcoming = upcomingSessionMuscles(
            history: history,
            through: day,
            muscleMaps: muscleMaps,
            emphasis: emphasis,
            remainingSessions: remainingSessions,
            calendar: calendar
        )

        var weeklyTargets: [MuscleGroup: Int] = [:]
        for (muscle, state) in mesocycle.muscles {
            weeklyTargets[muscle] = PlanKit.weeklyHardSetTarget(for: state)
        }

        return PlanKit.scheduledSets(
            weeklyTargets: weeklyTargets,
            loggedSets: logged,
            upcomingTargetMuscles: upcoming
        )
    }

    /// Next remaining training sessions this week (not every calendar day).
    private static func upcomingSessionMuscles(
        history: PrescriptionHistory,
        through day: HelmDay,
        muscleMaps: [String: ExerciseMuscleMap],
        emphasis: String?,
        remainingSessions: Int,
        calendar: Calendar
    ) -> [[MuscleGroup]] {
        let rotation = SessionSplitPlanner.rotationSplits(emphasis: emphasis)
        let completedSplits = completedSplitKinds(
            in: history,
            through: day,
            muscleMaps: muscleMaps,
            calendar: calendar
        )
        var pending = rotation.filter { !completedSplits.contains($0) }
        // Only recycle the full rotation when sessions remain and every split was already hit.
        if pending.isEmpty, remainingSessions > 0 {
            pending = rotation
        }
        guard !pending.isEmpty else { return [] }

        var upcoming: [[MuscleGroup]] = []
        var source = pending
        while upcoming.count < remainingSessions {
            for split in source {
                upcoming.append(split.muscles)
                if upcoming.count >= remainingSessions { break }
            }
            source = rotation
        }
        return upcoming
    }

    private static func completedSplitKinds(
        in history: PrescriptionHistory,
        through endDay: HelmDay,
        muscleMaps: [String: ExerciseMuscleMap],
        calendar: Calendar
    ) -> [SessionSplitKind] {
        let weekDays = (0 ..< 7).map { history.weekStart.adding(days: $0, calendar: calendar) }
        let weekDaySet = Set(weekDays)
        var completed: [SessionSplitKind] = []

        for session in history.sessions where weekDaySet.contains(session.helmDay) && session.helmDay <= endDay {
            var muscles = Set<MuscleGroup>()
            let exerciseIDs = Set(session.sets.map(\.exerciseID))
            for exerciseID in exerciseIDs {
                guard let map = muscleMaps[exerciseID] else { continue }
                for contribution in map.contributions where contribution.fraction >= 0.25 {
                    muscles.insert(contribution.muscle)
                }
            }
            if let kind = SessionSplitPlanner.inferSplitKind(from: muscles), !completed.contains(kind) {
                completed.append(kind)
            }
        }
        return completed
    }

    static func buildE1RMPage(
        store: PersistenceStore,
        exerciseID: String,
        offset: Int,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> (points: [E1RMProgressionPoint], canLoadMore: Bool) {
        let rows = try store.workoutSessions.fetchE1RMHistory(
            exerciseID: exerciseID,
            limit: pageSize,
            offset: offset,
            calendar: calendar,
            cutoff: cutoff
        )
        let points = rows
            .map {
                E1RMProgressionPoint(
                    helmDay: $0.helmDay,
                    achievedAt: $0.achievedAt,
                    e1RMKilograms: $0.e1RMKilograms
                )
            }
            .sorted { $0.achievedAt < $1.achievedAt }

        return (points, rows.count == pageSize)
    }

    static func buildEnergyBalancePage(
        store: PersistenceStore,
        endingAt endDay: HelmDay,
        offset: Int,
        calendar: Calendar = .current
    ) throws -> (gauges: [EnergyBalanceGauge], canLoadMore: Bool) {
        let days = try store.nutrition.fetchDays(endingAt: endDay, limit: pageSize, offset: offset)
        let settings = try store.trainingPlan.load()
        let trendStore = NutritionTrendStore(metadata: store.appMetadata)
        let trend = try trendStore.load()
        let bodyProfileStore = BodyProfileStore(metadata: store.appMetadata)
        let storedProfile = bodyProfileStore.load()

        let gauges = days.compactMap { day -> EnergyBalanceGauge? in
            guard let intake = day.totalEnergy?.kilocalories else { return nil }
            let bodyMassKg = try? store.bodyComposition
                .fetchLatest(onOrBefore: day.helmDay, limit: 1)
                .first?
                .mass
                .kilograms
            var bodyProfile = storedProfile
            if let bodyMassKg, bodyMassKg > 1, var profile = bodyProfile {
                profile = profile.withUpdatedBodyMassKg(bodyMassKg)
                bodyProfile = profile
            }
            let targets = NutritionKit.targets(
                for: NutritionTargetContext(
                    bodyProfile: bodyProfile,
                    dayType: .rest,
                    loggedDay: day
                ),
                phase: settings.phaseGoal,
                trend: trend
            )
            let target = Double(targets.caloriesKcal)
            guard target > 0 else { return nil }
            return EnergyBalanceGauge(
                helmDay: day.helmDay,
                intakeKcal: intake,
                targetKcal: target,
                state: HelmState.energyBalance(intakeKcal: intake, targetKcal: target)
            )
        }
        .sorted { $0.helmDay < $1.helmDay }

        return (gauges, days.count == pageSize)
    }

    static func resolveExercise(
        store: PersistenceStore,
        preferredID: String?
    ) throws -> (id: String, name: String) {
        if let preferredID,
           let summary = try store.exercises.fetchSummary(id: preferredID) {
            return (preferredID, summary.displayName)
        }

        let staples = ["exercise-squat", "exercise-bench-press", "exercise-deadlift"]
        for staple in staples {
            if let summary = try store.exercises.fetchSummary(id: staple) {
                return (staple, summary.displayName)
            }
        }

        let fallback = try store.exercises.listForPicker(limit: 1).first
        return (fallback?.id ?? defaultExerciseID, fallback?.displayName ?? "Squat")
    }

    static func weekStart(containing day: HelmDay, calendar: Calendar) -> HelmDay {
        var iso = calendar
        iso.firstWeekday = 2
        let components = day.dateComponents()
        guard
            let date = iso.date(from: components),
            let interval = iso.dateInterval(of: .weekOfYear, for: date)
        else {
            return day
        }
        return HelmDay.day(for: interval.start, cutoff: .default, calendar: iso)
    }

    private static func trendWeightState(trendKg: Double, targetKg: Double?) -> HelmState {
        guard let targetKg, targetKg > 0 else { return .ready }
        let delta = abs(trendKg - targetKg)
        if delta <= 0.3 { return .primed }
        if delta <= 1.0 { return .ready }
        if delta <= 2.5 { return .compromised }
        return .depleted
    }

    static func loadMesocycleState(from store: PersistenceStore) throws -> MesocycleState? {
        guard let json = try store.plan.loadMesocycleStateJSON(),
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(MesocycleState.self, from: data)
    }

    static func muscleMaps(from store: PersistenceStore) throws -> [String: ExerciseMuscleMap] {
        let rows = try store.exercises.fetchCatalogRows()
        var maps: [String: ExerciseMuscleMap] = [:]
        for row in rows {
            guard let map = muscleMap(for: row) else { continue }
            maps[row.id] = map
        }
        return maps
    }

    private static func muscleMap(for row: ExerciseCatalogRow) -> ExerciseMuscleMap? {
        var contributions: [ExerciseMuscleContribution] = []
        if let primary = row.primaryMuscleGroup, let muscle = mapMuscle(primary) {
            contributions.append(ExerciseMuscleContribution(muscle: muscle, fraction: 0.7))
        }
        let secondaryMuscles = row.secondaryMuscleGroups.compactMap(mapMuscle)
        if secondaryMuscles.isEmpty, contributions.isEmpty {
            return nil
        }
        if secondaryMuscles.isEmpty {
            contributions[0] = ExerciseMuscleContribution(muscle: contributions[0].muscle, fraction: 1.0)
        } else {
            let secondaryFraction = (1.0 - contributions.reduce(0.0) { $0 + $1.fraction })
                / Double(secondaryMuscles.count)
            for muscle in secondaryMuscles {
                contributions.append(
                    ExerciseMuscleContribution(muscle: muscle, fraction: max(0.05, secondaryFraction))
                )
            }
            normalizeContributions(&contributions)
        }
        return ExerciseMuscleMap(exerciseID: row.id, contributions: contributions)
    }

    private static func normalizeContributions(_ contributions: inout [ExerciseMuscleContribution]) {
        let total = contributions.reduce(0.0) { $0 + $1.fraction }
        guard total > 0 else { return }
        contributions = contributions.map {
            ExerciseMuscleContribution(muscle: $0.muscle, fraction: $0.fraction / total)
        }
    }

    private static func mapMuscle(_ slug: String) -> MuscleGroup? {
        switch slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "chest": .chest
        case "shoulders": .shoulders
        case "biceps": .biceps
        case "triceps": .triceps
        case "quadriceps", "quads": .quads
        case "hamstrings": .hamstrings
        case "glutes": .glutes
        case "calves": .calves
        case "abs", "abdominals": .abs
        case "lats", "upper back", "middle back", "traps", "lower back", "back": .back
        default: nil
        }
    }

    static func loadSessionsForSummary(
        store: PersistenceStore,
        since startDay: HelmDay,
        calendar: Calendar,
        cutoff: DayCutoff
    ) throws -> [WorkoutSession] {
        var sessions: [WorkoutSession] = []
        var offset = 0

        while true {
            let ids = try store.workoutSessions.listCompletedSessionIDs(
                since: startDay,
                limit: sessionPageSize,
                offset: offset,
                calendar: calendar,
                cutoff: cutoff
            )
            guard !ids.isEmpty else { break }

            for id in ids {
                guard let draft = try store.workoutSessions.fetch(id: id) else { continue }
                sessions.append(workoutSession(from: draft, calendar: calendar, cutoff: cutoff))
            }

            offset += ids.count
            if ids.count < sessionPageSize { break }
        }

        return sessions
    }

    private static func workoutSession(
        from draft: WorkoutSessionDraft,
        calendar: Calendar,
        cutoff: DayCutoff
    ) -> WorkoutSession {
        let helmDay = HelmDay.day(for: draft.startedAt, cutoff: cutoff, calendar: calendar)
        var sessionSets: [LoggedSet] = []
        var sequence = 0

        for exercise in draft.exercises {
            for set in exercise.sets where set.status == .completed {
                sequence += 1
                sessionSets.append(
                    LoggedSet(
                        exerciseID: exercise.exerciseID,
                        sequence: sequence,
                        mass: set.mass,
                        reps: set.reps,
                        rir: set.rir.map { Int($0.rounded()) },
                        rpe: set.rpe,
                        completedAt: set.completedAt ?? draft.startedAt,
                        setType: set.setType
                    )
                )
            }
        }

        return WorkoutSession(
            id: UUID(uuidString: draft.id) ?? UUID(),
            helmDay: helmDay,
            startedAt: draft.startedAt,
            finishedAt: draft.endedAt,
            sets: sessionSets
        )
    }
}
