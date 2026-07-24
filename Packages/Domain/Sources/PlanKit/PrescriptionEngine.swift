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

        var exercises: [PrescribedExercise] = []
        var order = 0
        var selectedExerciseIDs: Set<String> = []

        for muscle in profile.targetMuscles {
            guard let muscleState = profile.mesocycleState.muscles[muscle] else { continue }
            guard let selection = ExerciseSelectionEngine.select(
                for: muscle,
                catalog: profile.exerciseCatalog,
                excluding: selectedExerciseIDs,
                availableEquipment: profile.availableEquipment,
                selectionBias: profile.selectionBias,
                familiarExerciseIDs: profile.familiarExerciseIDs
            ) else { continue }

            let catalogExercise = selection.exercise
            selectedExerciseIDs.insert(catalogExercise.exerciseID)

            let weeklyTarget = MesocycleEngine.weeklyHardSetTarget(for: muscleState)
            let doneThisWeek = weeklyLedger.totals[muscle, default: 0]
            let remaining = max(0, Double(weeklyTarget) - doneThisWeek)
            let baseSets = max(
                1,
                Int(ceil(remaining / Double(profile.remainingSessionsThisWeek)))
            )
            let gatedSets = PrescriptionBounds.clampSets(
                Int((Double(baseSets) * gating.volumeMultiplier * phaseMultiplier).rounded())
            )

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

    private static func phaseVolumeMultiplier(for phase: TrainingPhase) -> Double {
        switch phase {
        case .cut: 0.85
        case .maintain: 1.0
        case .gain: 1.0
        }
    }
}
