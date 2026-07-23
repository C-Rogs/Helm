import Core
import Foundation

/// PLAN-facing name for the daily ready-to-go session prescription.
public typealias PrescribedSession = SessionPrescription

/// A canonical exercise available for selection and swap fallback.
public struct CatalogExercise: Sendable, Hashable, Codable {
    public let exerciseID: String
    public let muscleMap: ExerciseMuscleMap
    /// Lower values are preferred when multiple exercises train the same muscle.
    public let priority: Int

    public init(exerciseID: String, muscleMap: ExerciseMuscleMap, priority: Int) {
        self.exerciseID = exerciseID
        self.muscleMap = muscleMap
        self.priority = priority
    }
}

/// Inputs for computing a daily prescription. Pure value type; no I/O.
public struct PrescriptionProfile: Sendable, Hashable, Codable {
    public let helmDay: HelmDay
    public let phaseGoal: PhaseGoal
    public let mesocycleState: MesocycleState
    public let experience: TrainingExperience
    /// Muscles to train in this session.
    public let targetMuscles: [MuscleGroup]
    /// Exercises available for selection and swap fallback.
    public let exerciseCatalog: [CatalogExercise]
    /// Planned sessions still to run this week after today (including today).
    public let remainingSessionsThisWeek: Int

    public init(
        helmDay: HelmDay,
        phaseGoal: PhaseGoal,
        mesocycleState: MesocycleState,
        experience: TrainingExperience,
        targetMuscles: [MuscleGroup],
        exerciseCatalog: [CatalogExercise],
        remainingSessionsThisWeek: Int = 2
    ) {
        precondition(remainingSessionsThisWeek >= 1, "remainingSessionsThisWeek must be >= 1")
        self.helmDay = helmDay
        self.phaseGoal = phaseGoal
        self.mesocycleState = mesocycleState
        self.experience = experience
        self.targetMuscles = targetMuscles
        self.exerciseCatalog = exerciseCatalog
        self.remainingSessionsThisWeek = remainingSessionsThisWeek
    }
}

/// Logged training history consumed by the prescription engine.
public struct PrescriptionHistory: Sendable, Hashable, Codable {
    public let loggedSets: [LoggedSet]
    public let sessions: [WorkoutSession]
    public let weekStart: HelmDay

    public init(
        loggedSets: [LoggedSet],
        sessions: [WorkoutSession] = [],
        weekStart: HelmDay
    ) {
        self.loggedSets = loggedSets
        self.sessions = sessions
        self.weekStart = weekStart
    }
}
