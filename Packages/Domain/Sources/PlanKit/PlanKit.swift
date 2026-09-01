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
    ///
    /// Supply `muscle` and `experience` to bound how far repeated refinement can carry
    /// landmarks away from their physiological seed.
    public static func refineLandmarks(
        _ landmarks: VolumeLandmarks,
        signals: ToleranceSignals,
        muscle: MuscleGroup? = nil,
        experience: TrainingExperience = .intermediate
    ) -> VolumeLandmarks {
        let bounds = muscle.map {
            MesocycleEngine.LandmarkBounds.forMuscle($0, experience: experience)
        } ?? .permissive
        return MesocycleEngine.refineLandmarks(landmarks, signals: signals, bounds: bounds)
    }

    /// Reseed landmarks mid-block when experience or history profile changes.
    public static func reseedLandmarks(
        current: VolumeLandmarks,
        newSeed: VolumeLandmarks
    ) -> VolumeLandmarks {
        MesocycleEngine.reseedLandmarks(current: current, newSeed: newSeed)
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

    /// Per-lift progression from logged set history (Epley e1RM, working weight, next prescribed reps).
    /// `targetRIR` is today's intended proximity (RPE 8 → 2). Easy last sets climb more than 1 rep.
    public static func progression(
        for exerciseID: String,
        history: [LoggedSet],
        muscleMap: ExerciseMuscleMap? = nil,
        targetRIR: Double = 2.0
    ) -> LiftProgression {
        ProgressionEngine.progression(
            for: exerciseID,
            history: history,
            muscleMap: muscleMap,
            targetRIR: targetRIR
        )
    }

    /// Epley estimated 1RM for a single set.
    public static func estimatedOneRepMax(mass: Mass, reps: Int) -> Mass {
        ProgressionEngine.estimatedOneRepMax(mass: mass, reps: reps)
    }

    /// Snap a proposed load to the nearest loadable weight.
    public static func snapLoad(_ proposed: Mass, to increment: LoadIncrement) -> Mass {
        LoadRounding.snap(proposed, to: increment)
    }

    /// Snap a progressed load so rounding never cancels an intended increase or decrease.
    public static func snapLoadProgression(
        from current: Mass,
        proposed: Mass,
        increment: LoadIncrement
    ) -> Mass {
        LoadRounding.snapProgression(from: current, proposed: proposed, increment: increment)
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
        weekStart: HelmDay,
        context: HardSetEvaluationContext? = nil
    ) -> WeeklyHardSetLedger {
        HardSetAccounting.weeklyHardSetTotals(
            sessions: sessions,
            muscleMaps: muscleMaps,
            weekStart: weekStart,
            context: context
        )
    }

    /// Build e1RM context for load-band hard-set gates from session history.
    public static func hardSetEvaluationContext(from sessions: [WorkoutSession]) -> HardSetEvaluationContext {
        HardSetAccounting.buildEvaluationContext(from: sessions)
    }

    /// Stimulus credit for one logged set (0 = not a hard set).
    public static func stimulusCredit(
        _ set: LoggedSet,
        context: HardSetEvaluationContext = .empty,
        policy: HardSetPolicy = .standard
    ) -> Double {
        HardSetAccounting.stimulusCredit(set, context: context, policy: policy)
    }

    /// Split stimulus and fatigue credit for one logged set.
    public static func ledgerCredit(
        _ set: LoggedSet,
        context: HardSetEvaluationContext = .empty,
        policy: HardSetPolicy = .standard
    ) -> SetLedgerCredit {
        HardSetAccounting.ledgerCredit(
            set,
            role: SetStimulusRole(set.setType),
            context: context,
            policy: policy
        )
    }

    /// Per-muscle direct, synergist, and fatigue volume for the week starting at `weekStart`.
    public static func weeklyVolumeBreakdown(
        sessions: [WorkoutSession],
        muscleMaps: [String: ExerciseMuscleMap],
        weekStart: HelmDay,
        policy: HardSetPolicy = .standard
    ) -> [MuscleGroup: MuscleVolumeBreakdown] {
        HardSetAccounting.weeklyVolumeBreakdown(
            sessions: sessions,
            muscleMaps: muscleMaps,
            weekStart: weekStart,
            policy: policy
        )
    }

    /// Weekly hard sets still prescribable, limited by stimulus target and MRV alike.
    public static func remainingWeeklyHardSets(
        weeklyTarget: Int,
        breakdown: MuscleVolumeBreakdown,
        fatigueCeiling: Int? = nil,
        policy: HardSetPolicy = .standard
    ) -> Double {
        HardSetAccounting.remainingWeeklyHardSets(
            weeklyTarget: weeklyTarget,
            breakdown: breakdown,
            fatigueCeiling: fatigueCeiling,
            policy: policy
        )
    }

    /// Whether a drop-set row lacks a preceding top working set in the same exercise.
    public static func isOrphanDropSet(_ set: LoggedSet, priorSetsInExercise: [LoggedSet]) -> Bool {
        HardSetAccounting.isOrphanDropSet(set, priorSetsInExercise: priorSetsInExercise)
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
        calendar: Calendar = Calendar(identifier: .iso8601),
        policy: DriftPolicy = .default
    ) -> PlanAdjustment {
        DriftPolicyEngine.resolveDrift(
            planned: planned,
            actual: actual,
            calendar: calendar,
            policy: policy
        )
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

    /// Evidence-driven movement selection for a composer slot.
    public static func selectExercise(
        for slot: PatternSlot,
        catalog: [CatalogExercise],
        excluding excludedExerciseIDs: Set<String> = [],
        availableEquipment: Set<String>? = nil,
        selectionBias: MethodologyPreferences.SelectionBias = .balanced,
        familiarExerciseIDs: Set<String> = []
    ) -> ExerciseSelection? {
        ExerciseSelectionEngine.select(
            for: slot,
            catalog: catalog,
            excluding: excludedExerciseIDs,
            availableEquipment: availableEquipment,
            selectionBias: selectionBias,
            familiarExerciseIDs: familiarExerciseIDs
        )
    }

    /// Dry-run example session for a plan-builder candidate. Does not persist.
    public static func exampleWorkout(
        dayKind: TrainingDayKind,
        budget: SessionDurationBudget,
        template: ProgramTemplate,
        catalog: [CatalogExercise]
    ) -> [ExampleWorkoutLine] {
        let slots = sessionSlots(dayKind: dayKind, budget: budget, template: template)
        var excluded: Set<String> = []
        var lines: [ExampleWorkoutLine] = []
        for slot in slots {
            guard let selection = selectExercise(
                for: slot,
                catalog: catalog,
                excluding: excluded
            ) else { continue }
            excluded.insert(selection.exercise.exerciseID)
            let sets: Int
            switch slot.role {
            case .primary: sets = min(4, budget.maxSetsPerSlot)
            case .secondary: sets = min(3, budget.maxSetsPerSlot)
            case .isolation: sets = min(2, budget.maxSetsPerSlot)
            }
            lines.append(
                ExampleWorkoutLine(
                    exerciseID: selection.exercise.exerciseID,
                    pattern: slot.pattern,
                    targetSets: sets
                )
            )
        }
        return lines
    }
}

public struct ExampleWorkoutLine: Sendable, Equatable, Identifiable {
    public var id: String { exerciseID }

    public let exerciseID: String
    public let pattern: MovementPatternKind
    public let targetSets: Int

    public init(exerciseID: String, pattern: MovementPatternKind, targetSets: Int) {
        self.exerciseID = exerciseID
        self.pattern = pattern
        self.targetSets = targetSets
    }
}
