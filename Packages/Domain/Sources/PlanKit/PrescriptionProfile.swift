import Core
import Foundation

/// PLAN-facing name for the daily ready-to-go session prescription.
public typealias PrescribedSession = SessionPrescription

/// A canonical exercise available for selection and swap fallback.
public struct CatalogExercise: Sendable, Hashable, Codable {
    public let exerciseID: String
    public let muscleMap: ExerciseMuscleMap
    /// Lower values are preferred when evidence ratings are absent.
    public let priority: Int
    /// Normalized equipment tag (for example `barbell`, `dumbbell`). Nil means bodyweight/unspecified.
    public let equipment: String?
    public let evidence: ExerciseEvidenceRatings?

    public init(
        exerciseID: String,
        muscleMap: ExerciseMuscleMap,
        priority: Int,
        equipment: String? = nil,
        evidence: ExerciseEvidenceRatings? = nil
    ) {
        self.exerciseID = exerciseID
        self.muscleMap = muscleMap
        self.priority = priority
        self.equipment = equipment
        self.evidence = evidence
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
    /// When set, only exercises using this equipment (or bodyweight) are eligible.
    public let availableEquipment: Set<String>?
    public let selectionBias: MethodologyPreferences.SelectionBias
    /// Exercise IDs logged recently; selection engine prefers these over obscure catalog entries.
    public let familiarExerciseIDs: Set<String>

    public init(
        helmDay: HelmDay,
        phaseGoal: PhaseGoal,
        mesocycleState: MesocycleState,
        experience: TrainingExperience,
        targetMuscles: [MuscleGroup],
        exerciseCatalog: [CatalogExercise],
        remainingSessionsThisWeek: Int = 2,
        availableEquipment: Set<String>? = nil,
        selectionBias: MethodologyPreferences.SelectionBias = .balanced,
        familiarExerciseIDs: Set<String> = []
    ) {
        precondition(remainingSessionsThisWeek >= 1, "remainingSessionsThisWeek must be >= 1")
        self.helmDay = helmDay
        self.phaseGoal = phaseGoal
        self.mesocycleState = mesocycleState
        self.experience = experience
        self.targetMuscles = targetMuscles
        self.exerciseCatalog = exerciseCatalog
        self.remainingSessionsThisWeek = remainingSessionsThisWeek
        self.availableEquipment = availableEquipment
        self.selectionBias = selectionBias
        self.familiarExerciseIDs = familiarExerciseIDs
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
