import Core
import Foundation
import ReadinessKit

enum PrescriptionEngine {
    static func prescription(
        for profile: PrescriptionProfile,
        givenReadiness readiness: ReadinessScore?,
        history: PrescriptionHistory
    ) -> PrescribedSession {
        let gating = ReadinessGating.effect(for: readiness)
        let phaseMultiplier = phaseVolumeMultiplier(for: profile.phaseGoal.phase)
        let readinessVolumeScale = gating.usesOrderedVolumeTrim ? 1.0 : gating.volumeMultiplier
        let volumeMultiplier = readinessVolumeScale * phaseMultiplier
        let muscleMaps = Dictionary(uniqueKeysWithValues: profile.exerciseCatalog.map {
            ($0.exerciseID, $0.muscleMap)
        })
        let weeklyBreakdown = HardSetAccounting.weeklyVolumeBreakdown(
            sessions: history.sessions,
            muscleMaps: muscleMaps,
            weekStart: history.weekStart
        )

        let dayKind = profile.dayKind
            ?? TrainingDayKind.infer(from: profile.targetMuscles)
        let isDeload = profile.targetMuscles.contains { muscle in
            profile.mesocycleState.muscles[muscle]?.phase == .deload
        }
        let thinSession = SessionComposer.allowsThinSession(
            budget: profile.durationBudget,
            readinessBand: readiness?.band,
            isDeload: isDeload
        )
        let slots = SessionComposer.slots(
            dayKind: dayKind,
            budget: profile.durationBudget,
            template: profile.programTemplate,
            readinessBand: readiness?.band,
            isDeload: isDeload
        ).filter { !profile.excludedPatterns.contains($0.pattern) }

        let selectionCatalog = filteredCatalog(for: profile)

        var remainingByMuscle: [MuscleGroup: Double] = [:]
        for muscle in SessionComposer.primaryMuscles(in: slots) {
            guard let muscleState = profile.mesocycleState.muscles[muscle] else {
                remainingByMuscle[muscle] = Double(profile.durationBudget.maxSetsPerSlot)
                continue
            }
            let weeklyTarget = MesocycleEngine.weeklyHardSetTarget(for: muscleState)
            let breakdown = weeklyBreakdown[muscle] ?? MuscleVolumeBreakdown(direct: 0, synergist: 0)
            remainingByMuscle[muscle] = HardSetAccounting.remainingWeeklyHardSets(
                weeklyTarget: weeklyTarget,
                breakdown: breakdown,
                fatigueCeiling: muscleState.landmarks.mrv
            )
        }

        var candidates: [SlotAllocationCandidate] = []
        var selectedExerciseIDs: Set<String> = []

        for slot in slots {
            guard let selection = ExerciseSelectionEngine.select(
                for: slot,
                catalog: selectionCatalog,
                excluding: selectedExerciseIDs,
                availableEquipment: profile.availableEquipment,
                selectionBias: profile.selectionBias,
                familiarExerciseIDs: profile.familiarExerciseIDs
            ) else {
                continue
            }
            selectedExerciseIDs.insert(selection.exercise.exerciseID)
            candidates.append(SlotAllocationCandidate(
                slot: slot,
                exercise: selection.exercise,
                rationale: selection.rationale,
                evidenceIDs: selection.evidenceIDs
            ))
        }

        let allocations = SessionSetAllocator.allocate(
            candidates: candidates,
            budget: profile.durationBudget,
            thinSession: thinSession || isDeload,
            volumeMultiplier: volumeMultiplier,
            remainingByMuscle: remainingByMuscle
        )

        var exercises: [PrescribedExercise] = []
        var exerciseRoles: [String: PatternSlotRole] = [:]
        var order = 0
        for allocation in allocations {
            let catalogExercise = allocation.candidate.exercise
            let slot = allocation.candidate.slot

            let progression = ProgressionEngine.progression(
                for: catalogExercise.exerciseID,
                history: history.loggedSets,
                muscleMap: catalogExercise.muscleMap
            )
            let targetRPE = PrescriptionBounds.clampRPE(gating.targetRPE, cap: gating.rpeCap)

            var sets = allocation.sets
            // Phase multiplier is already applied to the allocator's session budget;
            // applying it here too would double-scale cut-phase volume.
            sets = PrescriptionBounds.clampSets(sets)

            exercises.append(PrescribedExercise(
                exerciseID: catalogExercise.exerciseID,
                order: order,
                targetSets: sets,
                targetRepMin: progression.targetRepMin,
                targetRepMax: progression.targetRepMax,
                targetMass: progression.workingWeight,
                targetRPE: targetRPE,
                rationale: allocation.candidate.rationale,
                evidenceIDs: allocation.candidate.evidenceIDs
            ))
            exerciseRoles[catalogExercise.exerciseID] = slot.role
            order += 1
        }

        let maxSessionSets = profile.durationBudget.maxTotalSets
        if exercises.count < profile.durationBudget.minimumExerciseFloor, !thinSession {
            let weeklyLedger = HardSetAccounting.weeklyHardSetTotals(
                sessions: history.sessions,
                muscleMaps: muscleMaps,
                weekStart: history.weekStart
            )
            exercises = legacyMuscleFill(
                profile: profile,
                history: history,
                weeklyLedger: weeklyLedger,
                gating: gating,
                phaseMultiplier: phaseMultiplier,
                excluding: selectedExerciseIDs,
                startingOrder: order,
                existing: exercises,
                maxSessionSets: maxSessionSets,
                exerciseRoles: &exerciseRoles
            )
        }

        let weeklyLedger = HardSetAccounting.weeklyHardSetTotals(
            sessions: history.sessions,
            muscleMaps: muscleMaps,
            weekStart: history.weekStart
        )
        return autoregulatedSession(
            helmDay: profile.helmDay,
            exercises: exercises,
            gating: gating,
            profile: profile,
            muscleMaps: muscleMaps,
            weeklyLedger: weeklyLedger,
            exerciseRoles: exerciseRoles
        )
    }

    private static func autoregulatedSession(
        helmDay: HelmDay,
        exercises: [PrescribedExercise],
        gating: ReadinessGatingEffect,
        profile: PrescriptionProfile,
        muscleMaps: [String: ExerciseMuscleMap],
        weeklyLedger: WeeklyHardSetLedger,
        exerciseRoles: [String: PatternSlotRole]
    ) -> PrescribedSession {
        let session = PrescribedSession(helmDay: helmDay, exercises: exercises)
        return SessionAutoregulator.apply(
            session: session,
            gating: gating,
            context: SessionAutoregulationContext(
                exerciseRoles: exerciseRoles,
                muscleMaps: muscleMaps,
                mesocycleState: profile.mesocycleState,
                weeklyLedger: weeklyLedger,
                remainingSessionsThisWeek: profile.remainingSessionsThisWeek
            )
        )
    }

    static func bestExercise(
        for muscle: MuscleGroup,
        catalog: [CatalogExercise],
        excluding excludedExerciseIDs: Set<String>,
        availableEquipment: Set<String>? = nil,
        selectionBias: MethodologyPreferences.SelectionBias = .balanced,
        familiarExerciseIDs: Set<String> = []
    ) -> CatalogExercise? {
        ExerciseSelectionEngine.select(
            for: muscle,
            catalog: catalog,
            excluding: excludedExerciseIDs,
            availableEquipment: availableEquipment,
            selectionBias: selectionBias,
            familiarExerciseIDs: familiarExerciseIDs
        )?.exercise
    }

    private static func legacyMuscleFill(
        profile: PrescriptionProfile,
        history: PrescriptionHistory,
        weeklyLedger: WeeklyHardSetLedger,
        gating: ReadinessGatingEffect,
        phaseMultiplier: Double,
        excluding: Set<String>,
        startingOrder: Int,
        existing: [PrescribedExercise],
        maxSessionSets: Int,
        exerciseRoles: inout [String: PatternSlotRole]
    ) -> [PrescribedExercise] {
        var exercises = existing
        var order = startingOrder
        var selected = excluding
        var sessionSets = exercises.reduce(0) { $0 + $1.targetSets }
        let readinessVolumeScale = gating.usesOrderedVolumeTrim ? 1.0 : gating.volumeMultiplier
        let volumeMultiplier = readinessVolumeScale * phaseMultiplier
        let thinSession = false

        for muscle in profile.targetMuscles {
            if sessionSets >= maxSessionSets { break }
            guard let muscleState = profile.mesocycleState.muscles[muscle] else { continue }
            guard let selection = ExerciseSelectionEngine.select(
                for: muscle,
                catalog: filteredCatalog(for: profile),
                excluding: selected,
                availableEquipment: profile.availableEquipment,
                selectionBias: profile.selectionBias,
                familiarExerciseIDs: profile.familiarExerciseIDs
            ) else { continue }

            let weeklyTarget = MesocycleEngine.weeklyHardSetTarget(for: muscleState)
            let doneThisWeek = weeklyLedger.totals[muscle, default: 0]
            let remaining = max(0, Double(weeklyTarget) - doneThisWeek)
            let bounds = SessionSetAllocator.roleBounds(role: .primary, thinSession: thinSession)
            var gatedSets = PrescriptionBounds.clampSets(
                Int((Double(bounds.min) * volumeMultiplier).rounded())
            )
            gatedSets = min(gatedSets, profile.durationBudget.maxSetsPerSlot)
            gatedSets = min(gatedSets, max(bounds.min, maxSessionSets - sessionSets))
            _ = remaining

            selected.insert(selection.exercise.exerciseID)
            exerciseRoles[selection.exercise.exerciseID] = .primary
            let progression = ProgressionEngine.progression(
                for: selection.exercise.exerciseID,
                history: history.loggedSets,
                muscleMap: selection.exercise.muscleMap
            )
            exercises.append(PrescribedExercise(
                exerciseID: selection.exercise.exerciseID,
                order: order,
                targetSets: gatedSets,
                targetRepMin: progression.targetRepMin,
                targetRepMax: progression.targetRepMax,
                targetMass: progression.workingWeight,
                targetRPE: PrescriptionBounds.clampRPE(gating.targetRPE, cap: gating.rpeCap),
                rationale: selection.rationale,
                evidenceIDs: selection.evidenceIDs
            ))
            order += 1
            sessionSets += gatedSets
        }
        return exercises
    }

    private static func filteredCatalog(for profile: PrescriptionProfile) -> [CatalogExercise] {
        profile.exerciseCatalog.filter { exercise in
            !profile.excludedPatterns.contains { pattern in
                MovementPatternMatcher.patternScore(exerciseID: exercise.exerciseID, pattern: pattern) > 0
            }
        }
    }

    private static func phaseVolumeMultiplier(for phase: TrainingPhase) -> Double {
        switch phase {
        case .cut: 0.85
        case .maintain: 1.0
        case .gain: 1.0
        }
    }
}
