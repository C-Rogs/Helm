import Core
import DesignSystem
import Foundation
import HealthKitIngest
import Persistence
import PlanKit
import ReadinessKit

enum ProgressionDetailBuilder {
    private static let loadIncrementPercent = 2.5
    private static let ladderHistoryLimit = 24

    static func load(
        store: PersistenceStore,
        engine: PlanPrescriptionEngine,
        readiness: ReadinessScore?,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) async throws -> ProgressionDetailModel {
        let today = HelmDay.day(for: .now, cutoff: cutoff, calendar: calendar)
        let settings = try await engine.loadTrainingPlan()
        let session = try await engine.computeSession(for: today, readiness: readiness)
        let history = try PrescriptionHistoryBuilder.history(
            from: store, endingAt: today, calendar: calendar, cutoff: cutoff
        )
        let mesocycle = try loadMesocycleState(from: store)
        let experience = TrainingExperience(rawValue: settings.experienceRaw) ?? .intermediate
        let gating = ReadinessGating.effect(for: readiness)
        let names = try store.exercises.displayNames(for: session.exercises.map(\.exerciseID))
        let muscleMaps = try muscleMaps(from: store)
        let ledger = PlanKit.weeklyHardSetTotals(
            sessions: history.sessions, muscleMaps: muscleMaps, weekStart: history.weekStart
        )
        let overrides = ScheduleWeekOverrides.fromStored(
            (try? store.scheduleOverrides.load()) ?? .empty,
            weekStart: history.weekStart
        )
        let plannedToday = (try? store.plan.fetchPlannedWorkouts(from: today, through: today)) ?? []
        let targetMuscles = SchedulePlanner.targetMuscles(
            for: today,
            settings: settings,
            history: history,
            muscleMaps: muscleMaps,
            plannedSessionJSON: plannedToday.first(where: { $0.status != "skipped" })?.sessionJSON,
            calendar: calendar,
            overrides: overrides
        )
        let muscles = buildMuscleRows(
            mesocycle: mesocycle, ledger: ledger, targetMuscles: targetMuscles, experience: experience
        )
        let representative = muscles.first
        let ladders = try buildLadders(
            session: session, loggedSets: history.loggedSets, names: names,
            store: store, calendar: calendar, cutoff: cutoff
        )
        return ProgressionDetailModel(
            phaseLabel: phaseLabel(for: settings.phaseGoal),
            experienceLabel: experienceLabel(experience),
            blockSummary: blockSummaryText(from: representative),
            isDeloadWeek: representative?.phaseLabel == "Deload",
            muscles: muscles,
            scheme: buildScheme(session: session, gating: gating),
            ladders: ladders,
            isColdStart: ladders.allSatisfy(\.steps.isEmpty)
        )
    }

    static func coldStartFallback() -> ProgressionDetailModel { .coldStartFixture }

    private static func buildMuscleRows(
        mesocycle: MesocycleState?, ledger: WeeklyHardSetLedger,
        targetMuscles: [MuscleGroup], experience: TrainingExperience
    ) -> [MesocycleMuscleRow] {
        let fallbackMuscles = mesocycle.map {
            Array($0.muscles.keys).sorted { $0.rawValue < $1.rawValue }
        } ?? []
        let muscles = targetMuscles.isEmpty ? fallbackMuscles : targetMuscles
        return muscles.map { muscle in
            let muscleState = mesocycle?.muscles[muscle] ?? MuscleMesocycleState(
                landmarks: PlanKit.seedLandmarks(muscle: muscle, experience: experience),
                blockLengthWeeks: 5, currentWeek: 1
            )
            let landmarks = muscleState.landmarks
            let weeklyDone = ledger.totals[muscle, default: 0]
            return MesocycleMuscleRow(
                id: muscle.rawValue, label: muscleLabel(muscle),
                currentWeek: muscleState.currentWeek, blockLengthWeeks: muscleState.blockLengthWeeks,
                phaseLabel: muscleState.phase == .deload ? "Deload" : "Accumulating",
                weeklyTarget: PlanKit.weeklyHardSetTarget(for: muscleState),
                weeklyDone: weeklyDone, mev: landmarks.mev, mrv: landmarks.mrv,
                state: HelmState.volumeWeekly(sets: weeklyDone, mev: landmarks.mev, mrv: landmarks.mrv)
            )
        }
    }

    private static func buildScheme(session: PrescribedSession, gating: ReadinessGatingEffect) -> ProgressionSchemeSummary {
        let repMins = session.exercises.compactMap(\.targetRepMin)
        let repMaxes = session.exercises.compactMap(\.targetRepMax)
        let repRange: String
        if let min = repMins.min(), let max = repMaxes.max() {
            repRange = min == max ? "\(min)" : "\(min)-\(max)"
        } else { repRange = "8-12" }
        let setCounts = session.exercises.map(\.targetSets)
        let setsPerSession: String
        if setCounts.isEmpty { setsPerSession = "3 / exercise" }
        else if let minSets = setCounts.min(), let maxSets = setCounts.max(), minSets != maxSets {
            setsPerSession = "\(minSets)-\(maxSets) / exercise"
        } else if let sets = setCounts.first { setsPerSession = "\(sets) / exercise" }
        else { setsPerSession = "3 / exercise" }
        return ProgressionSchemeSummary(
            repRange: repRange,
            rpeCap: formatRPE(gating.rpeCap, prefix: "RPE "),
            targetRPE: formatRPE(gating.targetRPE, prefix: "RPE "),
            loadIncrement: "+\(String(format: "%.1f", loadIncrementPercent))%",
            setsPerSession: setsPerSession
        )
    }

    private static func buildLadders(
        session: PrescribedSession, loggedSets: [LoggedSet], names: [String: String],
        store: PersistenceStore, calendar: Calendar, cutoff: DayCutoff
    ) throws -> [LiftLadderRow] {
        try session.exercises.sorted { $0.order < $1.order }.map { exercise in
            try buildLadder(
                exerciseID: exercise.exerciseID,
                displayName: names[exercise.exerciseID] ?? exercise.exerciseID,
                targetRepMin: exercise.targetRepMin, targetRepMax: exercise.targetRepMax,
                loggedSets: loggedSets, store: store, calendar: calendar, cutoff: cutoff
            )
        }
    }

    private static func buildLadder(
        exerciseID: String, displayName: String, targetRepMin: Int?, targetRepMax: Int?,
        loggedSets: [LoggedSet], store: PersistenceStore, calendar: Calendar, cutoff: DayCutoff
    ) throws -> LiftLadderRow {
        let progression = PlanKit.progression(for: exerciseID, history: loggedSets)
        let history = try store.workoutSessions.fetchE1RMHistory(
            exerciseID: exerciseID, limit: ladderHistoryLimit, calendar: calendar, cutoff: cutoff
        )
        var steps: [LiftLadderStep] = []
        var previousE1RM: Double?
        for (index, point) in history.reversed().enumerated() {
            let delta = previousE1RM.map { point.e1RMKilograms - $0 }
            steps.append(LiftLadderStep(
                id: "\(exerciseID)-\(index)", stepIndex: index + 1,
                title: String(format: "%.0f kg e1RM", point.e1RMKilograms),
                e1RMKilograms: point.e1RMKilograms, deltaKilograms: delta,
                isCompleted: true, achievedAtLabel: dayLabel(for: point.helmDay, calendar: calendar)
            ))
            previousE1RM = point.e1RMKilograms
        }
        let repRange = repRangeText(min: targetRepMin, max: targetRepMax)
        if let working = progression.workingWeight {
            steps.append(LiftLadderStep(
                id: "\(exerciseID)-next", stepIndex: steps.count + 1,
                title: "Next: \(formatMass(working)) × \(repRange)",
                e1RMKilograms: nil, deltaKilograms: nil, isCompleted: false, achievedAtLabel: nil
            ))
        }
        return LiftLadderRow(
            id: exerciseID, displayName: displayName,
            currentE1RMKilograms: progression.estimatedOneRepMax?.kilograms,
            workingWeightKilograms: progression.workingWeight?.kilograms,
            targetRepRange: repRange, steps: steps
        )
    }

    private static func loadMesocycleState(from store: PersistenceStore) throws -> MesocycleState? {
        guard let json = try store.plan.loadMesocycleStateJSON(),
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MesocycleState.self, from: data)
    }

    private static func muscleMaps(from store: PersistenceStore) throws -> [String: ExerciseMuscleMap] {
        try TrendsDataBuilder.muscleMaps(from: store)
    }

    private static func phaseLabel(for phaseGoal: PhaseGoal) -> String {
        var parts = [phaseGoal.phase.rawValue.capitalized]
        if let emphasis = phaseGoal.emphasis, !emphasis.isEmpty { parts.append(emphasis) }
        return parts.joined(separator: " · ")
    }

    private static func experienceLabel(_ experience: TrainingExperience) -> String {
        switch experience {
        case .novice: "Novice"; case .intermediate: "Intermediate"; case .advanced: "Advanced"
        }
    }

    private static func blockSummaryText(from muscle: MesocycleMuscleRow?) -> String {
        guard let muscle else { return "Week 1 of 5 · Accumulating" }
        return "Week \(muscle.currentWeek) of \(muscle.blockLengthWeeks) · \(muscle.phaseLabel)"
    }

    private static func muscleLabel(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: "Chest"; case .back: "Back"; case .shoulders: "Shoulders"
        case .biceps: "Biceps"; case .triceps: "Triceps"; case .quads: "Quads"
        case .hamstrings: "Hamstrings"; case .glutes: "Glutes"; case .calves: "Calves"; case .abs: "Abs"
        }
    }

    private static func repRangeText(min: Int?, max: Int?) -> String {
        switch (min, max) {
        case let (min?, max?) where min == max: return "\(min)"
        case let (min?, max?): return "\(min)-\(max)"
        case let (min?, nil): return "\(min)+"
        case let (nil, max?): return "up to \(max)"
        default: return "8-12"
        }
    }

    private static func formatMass(_ mass: Mass) -> String { String(format: "%.1f kg", mass.kilograms) }

    private static func formatRPE(_ value: Double, prefix: String) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(prefix)\(Int(value))" : String(format: "\(prefix)%.1f", value)
    }

    private static func dayLabel(for helmDay: HelmDay, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        guard let date = calendar.date(from: helmDay.dateComponents()) else {
            return "\(helmDay.month)/\(helmDay.day)"
        }
        return formatter.string(from: date)
    }
}
