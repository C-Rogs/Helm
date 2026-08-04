import Core
import Diagnostics
import Foundation
import OSLog
import Persistence
import PlanKit
import ReadinessKit

public enum PrescriptionDashboardState: Sendable, Equatable {
    case loading
    case awaitingCatalog
    case prescribed(PrescribedSessionSummary)

    public var summary: PrescribedSessionSummary? {
        if case let .prescribed(summary) = self {
            return summary
        }
        return nil
    }
}

public struct PrescribedExerciseSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let targetSets: Int
    public let targetRepRange: String
    public let targetLoad: String?
    public let targetRPE: String?

    public init(
        id: String,
        displayName: String,
        targetSets: Int,
        targetRepRange: String,
        targetLoad: String?,
        targetRPE: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.targetSets = targetSets
        self.targetRepRange = targetRepRange
        self.targetLoad = targetLoad
        self.targetRPE = targetRPE
    }
}

public struct PrescribedSessionSummary: Sendable, Equatable {
    public let phase: TrainingPhase
    public let emphasis: String?
    public let title: String
    public let summary: String
    public let rationale: [String]
    public let splitKind: SessionSplitKind
    public let exercises: [PrescribedExerciseSummary]
    public let totalSets: Int
    public let readinessAdjusted: Bool

    public init(
        phase: TrainingPhase,
        emphasis: String?,
        title: String = "",
        summary: String = "",
        rationale: [String] = [],
        splitKind: SessionSplitKind = .custom,
        exercises: [PrescribedExerciseSummary],
        totalSets: Int,
        readinessAdjusted: Bool
    ) {
        self.phase = phase
        self.emphasis = emphasis
        self.title = title
        self.summary = summary
        self.rationale = rationale
        self.splitKind = splitKind
        self.exercises = exercises
        self.totalSets = totalSets
        self.readinessAdjusted = readinessAdjusted
    }

    public var coachPromptSeed: String {
        let bullets = rationale.map { "• \($0)" }.joined(separator: "\n")
        return "Today's session is \(title): \(summary).\n\(bullets)"
    }
}

@MainActor
@Observable
public final class PrescriptionService {
    public private(set) var state: PrescriptionDashboardState = .loading

    private let engine: PlanPrescriptionEngine

    public init(engine: PlanPrescriptionEngine) {
        self.engine = engine
    }

    public func refresh(readiness: ReadinessScore?) async {
        do {
            state = try await engine.dashboardState(for: today(), readiness: readiness)
        } catch {
            await DiagnosticsLog.shared.capture(
                error: error,
                category: .planKit,
                message: "Prescription dashboard refresh failed"
            )
            state = .awaitingCatalog
        }
    }

    public func saveTrainingPlan(_ settings: StoredTrainingPlanSettings) async throws {
        try await engine.saveTrainingPlan(settings)
        PrescriptionDayStore.clear(for: today())
        await refresh(readiness: nil)
    }

    public func saveMethodologyPreferences(_ preferences: MethodologyPreferences) async throws {
        try await engine.saveMethodologyPreferences(preferences)
        PrescriptionDayStore.clear(for: today())
        await refresh(readiness: nil)
    }

    public func currentTrainingPlan() async throws -> StoredTrainingPlanSettings {
        try await engine.loadTrainingPlan()
    }

    public func pendingReactiveDeload() async throws -> Bool {
        try await engine.pendingReactiveDeload()
    }

    public func confirmReactiveDeload() async throws {
        try await engine.confirmReactiveDeload()
        PrescriptionDayStore.clear(for: today())
        await refresh(readiness: nil)
    }

    public func dismissReactiveDeload() async throws {
        try await engine.dismissReactiveDeload()
    }

    public func todaysPrescription(readiness: ReadinessScore?) async throws -> PrescribedSession {
        try await engine.computeSession(for: today(), readiness: readiness)
    }

    private func today(calendar: Calendar = .current, cutoff: DayCutoff = .default) -> HelmDay {
        HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar)
    }
}

public actor PlanPrescriptionEngine {
    private let persistence: PersistenceStore
    private let signpost: HelmSignpost
    private let log: Logger
    private let calendar: Calendar
    private let cutoff: DayCutoff
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    public init(
        persistence: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.persistence = persistence
        self.calendar = calendar
        self.cutoff = cutoff
        signpost = HelmSignpost(name: .prescriptionCompute, category: .planKit)
        log = helmLogger(category: .planKit)
        jsonEncoder = JSONEncoder()
        jsonDecoder = JSONDecoder()
    }

    public func loadTrainingPlan() throws -> StoredTrainingPlanSettings {
        try persistence.trainingPlan.load()
    }

    public func pendingReactiveDeload() throws -> Bool {
        let state = try loadMesocycleStateSnapshot()
        return state.pendingReactiveDeload
    }

    public func confirmReactiveDeload() throws {
        var state = try loadMesocycleStateSnapshot()
        state = PlanKit.confirmReactiveDeload(state)
        try persistMesocycleState(state)
    }

    public func dismissReactiveDeload() throws {
        var state = try loadMesocycleStateSnapshot()
        state = PlanKit.dismissPendingReactiveDeload(state)
        try persistMesocycleState(state)
    }

    public func saveTrainingPlan(_ settings: StoredTrainingPlanSettings) throws {
        try persistence.trainingPlan.save(settings)
        try syncMemoryProfilePhaseGoal(settings.phaseGoal)
    }

    public func saveMethodologyPreferences(_ preferences: MethodologyPreferences) throws {
        var profile = try persistence.memoryProfile.load()
        profile.preferences = preferences.merge(into: profile.preferences)
        try persistence.memoryProfile.save(profile)
    }

    public func dashboardState(
        for day: HelmDay,
        readiness: ReadinessScore?
    ) throws -> PrescriptionDashboardState {
        let session = try computeSession(for: day, readiness: readiness)
        guard !session.exercises.isEmpty else {
            return .awaitingCatalog
        }

        let settings = try persistence.trainingPlan.load()
        let names = try persistence.exercises.displayNames(
            for: session.exercises.map(\.exerciseID)
        )
        let readinessAdjusted = readiness.map { $0.band == .depleted } ?? false

        let exercises = session.exercises.sorted(by: { $0.order < $1.order }).map { exercise in
            PrescribedExerciseSummary(
                id: exercise.exerciseID,
                displayName: names[exercise.exerciseID] ?? exercise.exerciseID,
                targetSets: exercise.targetSets,
                targetRepRange: repRangeText(min: exercise.targetRepMin, max: exercise.targetRepMax),
                targetLoad: loadText(exercise.targetMass),
                targetRPE: exercise.targetRPE.map { String(format: "RPE %.1f", $0) }
            )
        }

        let totalSets = exercises.reduce(0) { $0 + $1.targetSets }
        let brief = try sessionDesignBrief(
            for: day,
            settings: settings,
            session: session,
            totalSets: totalSets,
            exerciseCount: exercises.count,
            readiness: readiness
        )

        return .prescribed(
            PrescribedSessionSummary(
                phase: settings.phaseGoal.phase,
                emphasis: settings.phaseGoal.emphasis,
                title: brief.title,
                summary: brief.summary,
                rationale: brief.rationale,
                splitKind: brief.splitKind,
                exercises: exercises,
                totalSets: totalSets,
                readinessAdjusted: readinessAdjusted
            )
        )
    }

    public func computeSession(
        for day: HelmDay,
        readiness: ReadinessScore?
    ) throws -> PrescribedSession {
        PrescriptionDayStore.clearIfStale(currentDay: day)

        if let adjusted = PrescriptionDayStore.load(for: day), !adjusted.exercises.isEmpty {
            return adjusted
        }

        let settings = try persistence.trainingPlan.load()
        let experience = TrainingExperience(rawValue: settings.experienceRaw) ?? .intermediate
        let catalogRows = try persistence.exercises.fetchCatalogRows()
        let history = try PrescriptionHistoryBuilder.history(
            from: persistence,
            endingAt: day,
            calendar: calendar,
            cutoff: cutoff
        )
        let familiarExerciseIDs = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
        let catalog = PrescriptionCatalogBuilder.build(
            from: catalogRows,
            familiarExerciseIDs: familiarExerciseIDs
        )
        guard !catalog.isEmpty else {
            return PrescribedSession(helmDay: day, exercises: [])
        }

        let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map {
            ($0.exerciseID, $0.muscleMap)
        })
        let schedule = SchedulePlanner.plan(
            for: day,
            emphasis: settings.phaseGoal.emphasis,
            history: history,
            muscleMaps: muscleMaps,
            calendar: calendar
        )
        let targetMuscles = schedule.targetMuscles
        let completedThisWeek = PrescriptionHistoryBuilder.completedSessionsThisWeek(
            in: history,
            through: day
        )
        let mesocycleState = try loadOrCreateMesocycleState(
            targetMuscles: targetMuscles,
            experience: experience,
            history: history,
            muscleMaps: muscleMaps
        )
        var trackedMesocycle = PlanKit.recordReadinessForReactiveDeload(
            state: mesocycleState,
            band: readiness?.band
        )
        let methodology = try methodologyPreferences()
        let durationBudget = SessionDurationBudget.from(minutes: settings.sessionDurationMinutes)
        let programTemplate = ProgramTemplate(rawValue: settings.programTemplateRaw) ?? .ppl

        let profile = PrescriptionProfile(
            helmDay: day,
            phaseGoal: settings.phaseGoal,
            mesocycleState: trackedMesocycle,
            experience: experience,
            targetMuscles: targetMuscles,
            exerciseCatalog: catalog,
            remainingSessionsThisWeek: SessionSplitPlanner.remainingSessionsThisWeek(
                completedThisWeek: completedThisWeek
            ),
            availableEquipment: methodology.availableEquipmentFilter,
            selectionBias: methodology.selectionBias,
            familiarExerciseIDs: familiarExerciseIDs,
            durationBudget: durationBudget,
            programTemplate: programTemplate,
            dayKind: schedule.splitKind.trainingDayKind
        )

        let signpostID = signpost.makeSignpostID()
        signpost.begin(id: signpostID)
        var session = PlanKit.prescription(
            for: profile,
            givenReadiness: readiness,
            history: history
        )
        signpost.end(id: signpostID)

        let brief = SessionDesignBriefBuilder.build(
            splitKind: schedule.splitKind,
            targetMuscles: targetMuscles,
            phaseGoal: settings.phaseGoal,
            mesocycleState: trackedMesocycle,
            totalSets: session.exercises.reduce(0) { $0 + $1.targetSets },
            exerciseCount: session.exercises.count,
            readiness: readiness,
            scheduleNotes: schedule.scheduleNotes,
            weeklyLedger: PlanKit.weeklyHardSetTotals(
                sessions: history.sessions,
                muscleMaps: muscleMaps,
                weekStart: history.weekStart
            )
        )
        session = PrescribedSession(
            id: session.id,
            helmDay: session.helmDay,
            title: brief.title,
            exercises: session.exercises
        )

        try persistMesocycleState(trackedMesocycle)
        try persistPlannedWorkouts(
            startingAt: day,
            emphasis: settings.phaseGoal.emphasis,
            history: history,
            muscleMaps: muscleMaps
        )
        return session
    }

    public func saveAdjustedPrescription(_ prescription: PrescribedSession, for day: HelmDay) {
        PrescriptionDayStore.save(prescription, for: day)
    }

    private func sessionDesignBrief(
        for day: HelmDay,
        settings: StoredTrainingPlanSettings,
        session: PrescribedSession,
        totalSets: Int,
        exerciseCount: Int,
        readiness: ReadinessScore?
    ) throws -> SessionDesignBrief {
        let history = try PrescriptionHistoryBuilder.history(
            from: persistence,
            endingAt: day,
            calendar: calendar,
            cutoff: cutoff
        )
        let catalogRows = try persistence.exercises.fetchCatalogRows()
        let familiarExerciseIDs = PrescriptionHistoryBuilder.familiarExerciseIDs(from: history)
        let catalog = PrescriptionCatalogBuilder.build(
            from: catalogRows,
            familiarExerciseIDs: familiarExerciseIDs
        )
        let muscleMaps = Dictionary(uniqueKeysWithValues: catalog.map {
            ($0.exerciseID, $0.muscleMap)
        })
        let schedule = SchedulePlanner.plan(
            for: day,
            emphasis: settings.phaseGoal.emphasis,
            history: history,
            muscleMaps: muscleMaps,
            calendar: calendar
        )
        let mesocycleState = try loadOrCreateMesocycleState(
            targetMuscles: schedule.targetMuscles,
            experience: TrainingExperience(rawValue: settings.experienceRaw) ?? .intermediate,
            history: history,
            muscleMaps: muscleMaps
        )
        return SessionDesignBriefBuilder.build(
            splitKind: schedule.splitKind,
            targetMuscles: schedule.targetMuscles,
            phaseGoal: settings.phaseGoal,
            mesocycleState: trackedMesocycle,
            totalSets: totalSets,
            exerciseCount: exerciseCount,
            readiness: readiness,
            scheduleNotes: schedule.scheduleNotes,
            weeklyLedger: PlanKit.weeklyHardSetTotals(
                sessions: history.sessions,
                muscleMaps: muscleMaps,
                weekStart: history.weekStart
            )
        )
    }

    private func persistPlannedWorkouts(
        startingAt day: HelmDay,
        emphasis: String?,
        history: PrescriptionHistory,
        muscleMaps: [String: ExerciseMuscleMap]
    ) throws {
        let records = SchedulePlanner.plannedWorkoutRecords(
            startingAt: day,
            dayCount: 7,
            emphasis: emphasis,
            history: history,
            muscleMaps: muscleMaps,
            calendar: calendar
        )
        try persistence.plan.replacePlannedWorkouts(records)
    }

    private func loadMesocycleStateSnapshot() throws -> MesocycleState {
        if let json = try persistence.plan.loadMesocycleStateJSON(),
           let data = json.data(using: .utf8),
           let decoded = try? jsonDecoder.decode(MesocycleState.self, from: data),
           !decoded.muscles.isEmpty {
            return decoded
        }
        return MesocycleState()
    }

    private func loadOrCreateMesocycleState(
        targetMuscles: [MuscleGroup],
        experience: TrainingExperience,
        history: PrescriptionHistory,
        muscleMaps: [String: ExerciseMuscleMap]
    ) throws -> MesocycleState {
        if let json = try persistence.plan.loadMesocycleStateJSON(),
           let data = json.data(using: .utf8),
           let decoded = try? jsonDecoder.decode(MesocycleState.self, from: data),
           !decoded.muscles.isEmpty {
            return decoded
        }

        let muscles = Set(targetMuscles).sorted { $0.rawValue < $1.rawValue }
        let historical = historicalWeeklyHardSetAverages(
            history: history,
            muscleMaps: muscleMaps,
            endingAt: history.weekStart
        )
        let state = PlanKit.makeInitialState(
            muscles: muscles,
            experience: experience,
            historicalWeeklyHardSets: historical
        )
        try persistMesocycleState(state)
        return state
    }

    /// Mean weekly hard-set totals over the prior 8 calendar weeks (weeks with any volume only).
    private func historicalWeeklyHardSetAverages(
        history: PrescriptionHistory,
        muscleMaps: [String: ExerciseMuscleMap],
        endingAt endWeekStart: HelmDay,
        lookbackWeeks: Int = 8
    ) -> [MuscleGroup: Double] {
        var samples: [MuscleGroup: [Double]] = [:]
        for weekOffset in 0 ..< lookbackWeeks {
            let weekStart = endWeekStart.adding(days: -7 * weekOffset)
            let ledger = PlanKit.weeklyHardSetTotals(
                sessions: history.sessions,
                muscleMaps: muscleMaps,
                weekStart: weekStart
            )
            for (muscle, total) in ledger.totals where total > 0 {
                samples[muscle, default: []].append(total)
            }
        }
        return Dictionary(uniqueKeysWithValues: samples.compactMap { muscle, values in
            guard !values.isEmpty else { return nil }
            let mean = values.reduce(0, +) / Double(values.count)
            return (muscle, mean)
        })
    }

    private func persistMesocycleState(_ state: MesocycleState) throws {
        let data = try jsonEncoder.encode(state)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PrescriptionServiceError.encodingFailed
        }
        try persistence.plan.saveMesocycleStateJSON(json)
    }

    private func syncMemoryProfilePhaseGoal(_ phaseGoal: PhaseGoal) throws {
        var profile = try persistence.memoryProfile.load()
        profile.phaseGoal = phaseGoal
        try persistence.memoryProfile.save(profile)
    }

    private func methodologyPreferences() throws -> MethodologyPreferences {
        let profile = try persistence.memoryProfile.load()
        return MethodologyPreferences.parse(from: profile.preferences).preferences
    }

    private func repRangeText(min: Int?, max: Int?) -> String {
        switch (min, max) {
        case let (min?, max?) where min == max:
            return "\(min) reps"
        case let (min?, max?):
            return "\(min)-\(max) reps"
        case let (min?, nil):
            return "\(min)+ reps"
        case let (nil, max?):
            return "up to \(max) reps"
        default:
            return "reps"
        }
    }

    private func loadText(_ mass: Mass?) -> String? {
        guard let mass else { return nil }
        return String(format: "%.1f kg", mass.kilograms)
    }
}

public enum PrescriptionServiceError: Error, Sendable {
    case encodingFailed
}
