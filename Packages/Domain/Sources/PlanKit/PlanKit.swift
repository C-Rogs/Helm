import Core
import Foundation
import ReadinessKit

/// Pure mesocycle and progression engine. Zero I/O.
public enum PlanKit {
    // MARK: - Mesocycle

    /// Seed MEV/MRV landmarks from training experience before tolerance data refines them.
    public static func seedLandmarks(
        muscle: MuscleGroup,
        experience: TrainingExperience,
        historicalWeeklyHardSets: Double? = nil
    ) -> VolumeLandmarks {
        MesocycleEngine.seedLandmarks(
            muscle: muscle,
            experience: experience,
            historicalWeeklyHardSets: historicalWeeklyHardSets
        )
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

    /// Scheduled deload target: max(MEV, round(0.5 * peak week)).
    public static func deloadWeeklyTarget(landmarks: VolumeLandmarks, blockLength: Int) -> Int {
        MesocycleEngine.deloadWeeklyTarget(landmarks: landmarks, blockLength: blockLength)
    }

    public static func recordReadinessForReactiveDeload(
        state: MesocycleState,
        band: ReadinessBand?,
        toleranceByMuscle: [MuscleGroup: ToleranceSignals] = [:]
    ) -> MesocycleState {
        ReactiveDeloadPolicy.recordReadinessDay(
            state: state,
            band: band,
            toleranceByMuscle: toleranceByMuscle
        )
    }

    public static func confirmReactiveDeload(_ state: MesocycleState) -> MesocycleState {
        ReactiveDeloadPolicy.confirmReactiveDeload(state)
    }

    public static func dismissPendingReactiveDeload(_ state: MesocycleState) -> MesocycleState {
        ReactiveDeloadPolicy.dismissPending(state)
    }

    /// Hard sets still on the calendar for each muscle (logged + upcoming session simulation).
    public static func scheduledSets(
        weeklyTargets: [MuscleGroup: Int],
        loggedSets: [MuscleGroup: Double],
        upcomingTargetMuscles: [[MuscleGroup]]
    ) -> [MuscleGroup: Double] {
        ScheduledVolumeForecast.scheduledSets(
            weeklyTargets: weeklyTargets,
            loggedSets: loggedSets,
            upcomingTargetMuscles: upcomingTargetMuscles
        )
    }

    /// Build an initial mesocycle for the given muscles.
    public static func makeInitialState(
        muscles: [MuscleGroup],
        experience: TrainingExperience,
        blockLengthWeeks: Int = 5,
        historicalWeeklyHardSets: [MuscleGroup: Double] = [:]
    ) -> MesocycleState {
        MesocycleEngine.makeInitialState(
            muscles: muscles,
            experience: experience,
            blockLengthWeeks: blockLengthWeeks,
            historicalWeeklyHardSets: historicalWeeklyHardSets
        )
    }

    /// Advance every muscle one week; deload weeks reset the block and refine landmarks.
    public static func advanceWeek(
        _ state: MesocycleState,
        toleranceByMuscle: [MuscleGroup: ToleranceSignals] = [:],
        experience: TrainingExperience = .intermediate,
        historicalWeeklyHardSets: [MuscleGroup: Double] = [:]
    ) -> MesocycleState {
        MesocycleEngine.advanceWeek(
            state,
            toleranceByMuscle: toleranceByMuscle,
            experience: experience,
            historicalWeeklyHardSets: historicalWeeklyHardSets
        )
    }

    // MARK: - Progression

    /// Per-lift progression from logged set history (Epley e1RM, working weight, rep targets).
    public static func progression(
        for exerciseID: String,
        history: [LoggedSet],
        muscleMap: ExerciseMuscleMap? = nil
    ) -> LiftProgression {
        ProgressionEngine.progression(for: exerciseID, history: history, muscleMap: muscleMap)
    }

    /// Epley estimated 1RM for a single set.
    public static func estimatedOneRepMax(mass: Mass, reps: Int) -> Mass {
        ProgressionEngine.estimatedOneRepMax(mass: mass, reps: reps)
    }

    /// Convert logged RPE to claimed RIR (10 - RPE), clamped to 0...10.
    public static func rirFromRPE(_ rpe: Double) -> Double {
        RIRConsistency.rirFromRPE(rpe)
    }

    /// Soft flag when reps + claimed RIR exceed historical e1RM capacity at this load.
    public static func rirConsistencyFlag(
        mass: Mass,
        reps: Int,
        claimedRIR: Double,
        historicalBestE1RM: Mass?,
        spareRepMargin: Double = 2.0
    ) -> RIRConsistencyFlag? {
        RIRConsistency.evaluate(
            mass: mass,
            reps: reps,
            claimedRIR: claimedRIR,
            historicalBestE1RM: historicalBestE1RM,
            spareRepMargin: spareRepMargin
        )
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

    /// Count fractional hard sets per muscle across the rolling window ending at `endDay`.
    public static func rollingHardSetTotals(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        endingAt endDay: HelmDay,
        windowDays: Int = 7
    ) -> WeeklyHardSetLedger {
        HardSetAccounting.rollingHardSetTotals(
            sessions: sessions,
            muscleMaps: muscleMaps,
            endingAt: endDay,
            windowDays: windowDays
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

    /// Apply structured in-session adjustments.
    ///
    /// Volume and intensity bounds shape engine-generated prescriptions only.
    /// An adjustment is rejected here when it cannot be resolved, never because
    /// the athlete asked for more than the engine would have prescribed.
    public static func apply(
        adjustment: PrescriptionAdjustment,
        to session: PrescribedSession,
        excluding excludedExerciseIDs: Set<String>,
        catalog: [CatalogExercise],
        availableEquipment: Set<String>? = nil,
        familiarExerciseIDs: Set<String> = []
    ) -> PrescriptionAdjustmentResult {
        PrescriptionAdjustmentEngine.apply(
            adjustment: adjustment,
            to: session,
            excluding: excludedExerciseIDs,
            catalog: catalog,
            availableEquipment: availableEquipment,
            familiarExerciseIDs: familiarExerciseIDs
        )
    }

    /// Evidence-driven movement selection for a target muscle.
    public static func selectExercise(
        for muscle: MuscleGroup,
        catalog: [CatalogExercise],
        excluding excludedExerciseIDs: Set<String> = [],
        availableEquipment: Set<String>? = nil,
        selectionBias: MethodologyPreferences.SelectionBias = .balanced,
        familiarExerciseIDs: Set<String> = []
    ) -> ExerciseSelection? {
        ExerciseSelectionEngine.select(
            for: muscle,
            catalog: catalog,
            excluding: excludedExerciseIDs,
            availableEquipment: availableEquipment,
            selectionBias: selectionBias,
            familiarExerciseIDs: familiarExerciseIDs
        )
    }

    /// Pattern-slot list for a training day (MPSC).
    public static func sessionSlots(
        dayKind: TrainingDayKind,
        budget: SessionDurationBudget,
        template: ProgramTemplate = .ppl,
        readinessBand: ReadinessBand? = nil,
        isDeload: Bool = false
    ) -> [PatternSlot] {
        SessionComposer.slots(
            dayKind: dayKind,
            budget: budget,
            template: template,
            readinessBand: readinessBand,
            isDeload: isDeload
        )
    }
}
