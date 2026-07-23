import Core
import Foundation
import ReadinessKit

/// Pure mesocycle and progression engine. Zero I/O.
public enum PlanKit {
    // MARK: - Mesocycle

    /// Seed MEV/MRV landmarks from training experience before tolerance data refines them.
    public static func seedLandmarks(
        muscle: MuscleGroup,
        experience: TrainingExperience
    ) -> VolumeLandmarks {
        MesocycleEngine.seedLandmarks(muscle: muscle, experience: experience)
    }

    /// Refine landmarks from logged tolerance signals at the end of a block.
    public static func refineLandmarks(
        _ landmarks: VolumeLandmarks,
        signals: ToleranceSignals
    ) -> VolumeLandmarks {
        MesocycleEngine.refineLandmarks(landmarks, signals: signals)
    }

    /// Weekly hard-set target for a muscle given its current mesocycle position.
    public static func weeklyHardSetTarget(for muscleState: MuscleMesocycleState) -> Int {
        MesocycleEngine.weeklyHardSetTarget(for: muscleState)
    }

    /// Build an initial mesocycle for the given muscles.
    public static func makeInitialState(
        muscles: [MuscleGroup],
        experience: TrainingExperience,
        blockLengthWeeks: Int = 5
    ) -> MesocycleState {
        MesocycleEngine.makeInitialState(
            muscles: muscles,
            experience: experience,
            blockLengthWeeks: blockLengthWeeks
        )
    }

    /// Advance every muscle one week; deload weeks reset the block and refine landmarks.
    public static func advanceWeek(
        _ state: MesocycleState,
        toleranceByMuscle: [MuscleGroup: ToleranceSignals] = [:]
    ) -> MesocycleState {
        MesocycleEngine.advanceWeek(state, toleranceByMuscle: toleranceByMuscle)
    }

    // MARK: - Progression

    /// Per-lift progression from logged set history (Epley e1RM, working weight, rep targets).
    public static func progression(for exerciseID: String, history: [LoggedSet]) -> LiftProgression {
        ProgressionEngine.progression(for: exerciseID, history: history)
    }

    /// Epley estimated 1RM for a single set.
    public static func estimatedOneRepMax(mass: Mass, reps: Int) -> Mass {
        ProgressionEngine.estimatedOneRepMax(mass: mass, reps: reps)
    }

    // MARK: - Hard-set accounting

    /// Count fractional hard sets per muscle across sessions in the week starting at `weekStart`.
    public static func weeklyHardSetTotals(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        weekStart: HelmDay
    ) -> WeeklyHardSetLedger {
        HardSetAccounting.weeklyHardSetTotals(
            sessions: sessions,
            muscleMaps: muscleMaps,
            weekStart: weekStart
        )
    }

    // MARK: - Plan drift

    public static func resolveDrift(
        planned: PlannedCalendar,
        actual: ActualCalendar,
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> PlanAdjustment {
        DriftPolicyEngine.resolveDrift(planned: planned, actual: actual, calendar: calendar)
    }

    public static func acuteChronicWorkloadRatio(
        dailyLoads: [HelmDay: Double],
        asOf day: HelmDay,
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> AcuteChronicWorkloadRatio {
        AcuteChronicWorkload.ratio(dailyLoads: dailyLoads, asOf: day, calendar: calendar)
    }

    // MARK: - Prescription

    /// Daily numeric prescription with readiness gating and mesocycle-driven volume.
    public static func prescription(
        for profile: PrescriptionProfile,
        givenReadiness readiness: ReadinessScore?,
        history: PrescriptionHistory
    ) -> PrescribedSession {
        PrescriptionEngine.prescription(for: profile, givenReadiness: readiness, history: history)
    }

    /// Apply structured in-session adjustments with safe-bound clamping.
    public static func apply(
        adjustment: PrescriptionAdjustment,
        to session: PrescribedSession,
        excluding excludedExerciseIDs: Set<String>,
        catalog: [CatalogExercise],
        availableEquipment: Set<String>? = nil
    ) -> PrescriptionAdjustmentResult {
        PrescriptionAdjustmentEngine.apply(
            adjustment: adjustment,
            to: session,
            excluding: excludedExerciseIDs,
            catalog: catalog,
            availableEquipment: availableEquipment
        )
    }

    /// Evidence-driven movement selection for a target muscle.
    public static func selectExercise(
        for muscle: MuscleGroup,
        catalog: [CatalogExercise],
        excluding excludedExerciseIDs: Set<String> = [],
        availableEquipment: Set<String>? = nil
    ) -> ExerciseSelection? {
        ExerciseSelectionEngine.select(
            for: muscle,
            catalog: catalog,
            excluding: excludedExerciseIDs,
            availableEquipment: availableEquipment
        )
    }
}
