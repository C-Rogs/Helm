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
    public let exercises: [PrescribedExerciseSummary]
    public let totalSets: Int
    public let readinessAdjusted: Bool

    public init(
        phase: TrainingPhase,
        emphasis: String?,
        exercises: [PrescribedExerciseSummary],
        totalSets: Int,
        readinessAdjusted: Bool
    ) {
        self.phase = phase
        self.emphasis = emphasis
        self.exercises = exercises
        self.totalSets = totalSets
        self.readinessAdjusted = readinessAdjusted
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
            state = .awaitingCatalog
        }
    }

    public func saveTrainingPlan(_ settings: StoredTrainingPlanSettings) async throws {
        try await engine.saveTrainingPlan(settings)
        await refresh(readiness: nil)
    }

    public func saveMethodologyPreferences(_ preferences: MethodologyPreferences) async throws {
        try await engine.saveMethodologyPreferences(preferences)
        await refresh(readiness: nil)
    }

    public func currentTrainingPlan() async throws -> StoredTrainingPlanSettings {
        try await engine.loadTrainingPlan()
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

        return .prescribed(
            PrescribedSessionSummary(
                phase: settings.phaseGoal.phase,
                emphasis: settings.phaseGoal.emphasis,
                exercises: exercises,
                totalSets: exercises.reduce(0) { $0 + $1.targetSets },
                readinessAdjusted: readinessAdjusted
            )
        )
    }

    public func computeSession(
        for day: HelmDay,
        readiness: ReadinessScore?
    ) throws -> PrescribedSession {
        let settings = try persistence.trainingPlan.load()
        let experience = TrainingExperience(rawValue: settings.experienceRaw) ?? .intermediate
        let catalogRows = try persistence.exercises.fetchCatalogRows()
        let catalog = PrescriptionCatalogBuilder.build(from: catalogRows)
        guard !catalog.isEmpty else {
            return PrescribedSession(helmDay: day, exercises: [])
        }

        let history = try PrescriptionHistoryBuilder.history(
            from: persistence,
            endingAt: day,
            calendar: calendar,
            cutoff: cutoff
        )
        let targetMuscles = SessionSplitPlanner.targetMuscles(
            for: day,
            emphasis: settings.phaseGoal.emphasis,
            calendar: calendar
        )
        let completedThisWeek = PrescriptionHistoryBuilder.completedSessionsThisWeek(
            in: history,
            through: day
        )
        let mesocycleState = try loadOrCreateMesocycleState(
            targetMuscles: targetMuscles,
            experience: experience
        )
        let methodology = try methodologyPreferences()

        let profile = PrescriptionProfile(
            helmDay: day,
            phaseGoal: settings.phaseGoal,
            mesocycleState: mesocycleState,
            experience: experience,
            targetMuscles: targetMuscles,
            exerciseCatalog: catalog,
            remainingSessionsThisWeek: SessionSplitPlanner.remainingSessionsThisWeek(
                completedThisWeek: completedThisWeek
            ),
            availableEquipment: methodology.availableEquipmentFilter,
            selectionBias: methodology.selectionBias
        )

        let signpostID = signpost.makeSignpostID()
        signpost.begin(id: signpostID)
        let session = PlanKit.prescription(
            for: profile,
            givenReadiness: readiness,
            history: history
        )
        signpost.end(id: signpostID)

        try persistMesocycleState(mesocycleState)
        return session
    }

    private func loadOrCreateMesocycleState(
        targetMuscles: [MuscleGroup],
        experience: TrainingExperience
    ) throws -> MesocycleState {
        if let json = try persistence.plan.loadMesocycleStateJSON(),
           let data = json.data(using: .utf8),
           let decoded = try? jsonDecoder.decode(MesocycleState.self, from: data),
           !decoded.muscles.isEmpty {
            return decoded
        }

        let muscles = Set(targetMuscles).sorted { $0.rawValue < $1.rawValue }
        let state = PlanKit.makeInitialState(muscles: muscles, experience: experience)
        try persistMesocycleState(state)
        return state
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
            return "\(min)–\(max) reps"
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
