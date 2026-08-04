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
        let muscleMaps = Dictionary(uniqueKeysWithValues: profile.exerciseCatalog.map {
            ($0.exerciseID, $0.muscleMap)
        })
        let weeklyLedger = HardSetAccounting.weeklyHardSetTotals(
            sessions: history.sessions,
            muscleMaps: muscleMaps,
            weekStart: history.weekStart
        )

        let dayKind = profile.dayKind
            ?? TrainingDayKind.infer(from: profile.targetMuscles)
        let isDeload = profile.targetMuscles.contains { muscle in
            profile.mesocycleState.muscles[muscle]?.phase == .deload
        }
        let slots = SessionComposer.slots(
            dayKind: dayKind,
            budget: profile.durationBudget,
            template: profile.programTemplate,
            readinessBand: readiness?.band,
            isDeload: isDeload
        )

        var remainingByMuscle: [MuscleGroup: Double] = [:]
        for muscle in SessionComposer.primaryMuscles(in: slots) {
            guard let muscleState = profile.mesocycleState.muscles[muscle] else {
                // Seed-less muscle (e.g. rear-delt shoulders on pull): use a light isolation default.
                remainingByMuscle[muscle] = Double(profile.durationBudget.maxSetsPerSlot)
                continue
            }
            let weeklyTarget = MesocycleEngine.weeklyHardSetTarget(for: muscleState)
            let doneThisWeek = weeklyLedger.totals[muscle, default: 0]
            remainingByMuscle[muscle] = max(0, Double(weeklyTarget) - doneThisWeek)
        }

        var slotsPerMuscle: [MuscleGroup: Int] = [:]
        for slot in slots {
            slotsPerMuscle[slot.primaryMuscle, default: 0] += 1
        }

        var exercises: [PrescribedExercise] = []
        var order = 0
        var selectedExerciseIDs: Set<String> = []
        var sessionSets = 0
        let maxSessionSets = profile.durationBudget.maxTotalSets

        for slot in slots {
            if sessionSets >= maxSessionSets { break }

            guard let selection = ExerciseSelectionEngine.select(
                for: slot,
                catalog: profile.exerciseCatalog,
                excluding: selectedExerciseIDs,
                availableEquipment: profile.availableEquipment,
                selectionBias: profile.selectionBias,
                familiarExerciseIDs: profile.familiarExerciseIDs
            ) else {
                if slot.required { continue }
                continue
            }

            let catalogExercise = selection.exercise
            let muscle = slot.primaryMuscle
            let remaining = remainingByMuscle[muscle, default: Double(profile.durationBudget.maxSetsPerSlot)]
            let muscleSlotCount = max(1, slotsPerMuscle[muscle, default: 1])
            let baseSets = max(
                1,
                Int(ceil(remaining / Double(max(profile.remainingSessionsThisWeek, 1)) / Double(muscleSlotCount)))
            )
            let roleScaled: Double = switch slot.role {
            case .primary: 1.0
            case .secondary: 0.85
            case .isolation: 0.75
            }
            var gatedSets = PrescriptionBounds.clampSets(
                Int((Double(baseSets) * roleScaled * gating.volumeMultiplier * phaseMultiplier).rounded())
            )
            gatedSets = min(gatedSets, profile.durationBudget.maxSetsPerSlot)
            gatedSets = min(gatedSets, max(1, maxSessionSets - sessionSets))

            selectedExerciseIDs.insert(catalogExercise.exerciseID)
            // Consume roughly one slot's share so later slots for same muscle shrink.
            remainingByMuscle[muscle] = max(0, remaining - Double(gatedSets))
            slotsPerMuscle[muscle, default: 1] = max(1, (slotsPerMuscle[muscle] ?? 1) - 1)

            let progression = ProgressionEngine.progression(
                for: catalogExercise.exerciseID,
                history: history.loggedSets
            )
            let targetRPE = PrescriptionBounds.clampRPE(gating.targetRPE, cap: gating.rpeCap)

            exercises.append(PrescribedExercise(
                exerciseID: catalogExercise.exerciseID,
                order: order,
                targetSets: gatedSets,
                targetRepMin: progression.targetRepMin,
                targetRepMax: progression.targetRepMax,
                targetMass: progression.workingWeight,
                targetRPE: targetRPE,
                rationale: selection.rationale,
                evidenceIDs: selection.evidenceIDs
            ))
            order += 1
            sessionSets += gatedSets
        }

        // If catalog was too thin for required density, fall back to legacy one-per-muscle fill.
        let thinOK = SessionComposer.allowsThinSession(
            budget: profile.durationBudget,
            readinessBand: readiness?.band,
            isDeload: isDeload
        )
        if exercises.count < profile.durationBudget.minimumExerciseFloor, !thinOK {
            exercises = legacyMuscleFill(
                profile: profile,
                readiness: readiness,
                history: history,
                weeklyLedger: weeklyLedger,
                gating: gating,
                phaseMultiplier: phaseMultiplier,
                excluding: selectedExerciseIDs,
                startingOrder: order,
                existing: exercises,
                sessionSets: &sessionSets,
                maxSessionSets: maxSessionSets
            )
        }

        return PrescribedSession(helmDay: profile.helmDay, exercises: exercises)
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
        readiness: ReadinessScore?,
        history: PrescriptionHistory,
        weeklyLedger: WeeklyHardSetLedger,
        gating: ReadinessGatingEffect,
        phaseMultiplier: Double,
        excluding: Set<String>,
        startingOrder: Int,
        existing: [PrescribedExercise],
        sessionSets: inout Int,
        maxSessionSets: Int
    ) -> [PrescribedExercise] {
        _ = readiness
        var exercises = existing
        var order = startingOrder
        var selected = excluding
        for muscle in profile.targetMuscles {
            if sessionSets >= maxSessionSets { break }
            guard let muscleState = profile.mesocycleState.muscles[muscle] else { continue }
            guard let selection = ExerciseSelectionEngine.select(
                for: muscle,
                catalog: profile.exerciseCatalog,
                excluding: selected,
                availableEquipment: profile.availableEquipment,
                selectionBias: profile.selectionBias,
                familiarExerciseIDs: profile.familiarExerciseIDs
            ) else { continue }

            let weeklyTarget = MesocycleEngine.weeklyHardSetTarget(for: muscleState)
            let doneThisWeek = weeklyLedger.totals[muscle, default: 0]
            let remaining = max(0, Double(weeklyTarget) - doneThisWeek)
            let baseSets = max(1, Int(ceil(remaining / Double(profile.remainingSessionsThisWeek))))
            var gatedSets = PrescriptionBounds.clampSets(
                Int((Double(baseSets) * gating.volumeMultiplier * phaseMultiplier).rounded())
            )
            gatedSets = min(gatedSets, profile.durationBudget.maxSetsPerSlot)
            gatedSets = min(gatedSets, max(1, maxSessionSets - sessionSets))

            selected.insert(selection.exercise.exerciseID)
            let progression = ProgressionEngine.progression(
                for: selection.exercise.exerciseID,
                history: history.loggedSets
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

    private static func phaseVolumeMultiplier(for phase: TrainingPhase) -> Double {
        switch phase {
        case .cut: 0.85
        case .maintain: 1.0
        case .gain: 1.0
        }
    }
}
