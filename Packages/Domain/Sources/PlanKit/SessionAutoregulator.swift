import Core
import Foundation

/// Inputs for post-fill readiness trimming. Built by the prescription engine after slot fill.
public struct SessionAutoregulationContext: Sendable, Hashable {
    public let exerciseRoles: [String: PatternSlotRole]
    public let muscleMaps: [String: ExerciseMuscleMap]
    public let mesocycleState: MesocycleState
    public let weeklyLedger: WeeklyHardSetLedger
    public let remainingSessionsThisWeek: Int

    public init(
        exerciseRoles: [String: PatternSlotRole],
        muscleMaps: [String: ExerciseMuscleMap],
        mesocycleState: MesocycleState,
        weeklyLedger: WeeklyHardSetLedger,
        remainingSessionsThisWeek: Int
    ) {
        self.exerciseRoles = exerciseRoles
        self.muscleMaps = muscleMaps
        self.mesocycleState = mesocycleState
        self.weeklyLedger = weeklyLedger
        self.remainingSessionsThisWeek = remainingSessionsThisWeek
    }
}

/// Applies same-day readiness precedence after MPSC slot fill.
///
/// Order matters: systemic RPE caps before volume cuts protect intensity quality;
/// isolation trims spare compounds for MEV; technique mode preserves pattern exposure when depleted.
enum SessionAutoregulator {
    private static let techniqueRPE = 6.0

    static func apply(
        session: PrescribedSession,
        gating: ReadinessGatingEffect,
        context: SessionAutoregulationContext
    ) -> PrescribedSession {
        guard gating.usesOrderedVolumeTrim else {
            let capped = applyRPECap(to: session.exercises, gating: gating)
            return PrescribedSession(
                id: session.id,
                helmDay: session.helmDay,
                title: session.title,
                exercises: capped
            )
        }

        var exercises = applyRPECap(to: session.exercises, gating: gating)
        let baselineTotal = totalSets(in: exercises)
        let targetTotal = max(
            minimumSessionSets(in: exercises, context: context),
            Int((Double(baselineTotal) * gating.volumeMultiplier).rounded())
        )
        var reductionNeeded = max(0, baselineTotal - targetTotal)

        if reductionNeeded > 0 {
            reductionNeeded = trimSets(
                in: &exercises,
                roles: [.isolation],
                reductionNeeded: reductionNeeded,
                context: context
            )
        }

        if reductionNeeded > 0 {
            reductionNeeded = trimSets(
                in: &exercises,
                roles: [.secondary, .primary],
                reductionNeeded: reductionNeeded,
                context: context,
                respectMEVFloor: true
            )
        }

        if reductionNeeded > 0 || gating.convertsRemainingToTechnique {
            exercises = convertToTechnique(exercises, rpe: techniqueRPE)
        }

        return PrescribedSession(
            id: session.id,
            helmDay: session.helmDay,
            title: session.title,
            exercises: exercises
        )
    }

    private static func applyRPECap(
        to exercises: [PrescribedExercise],
        gating: ReadinessGatingEffect
    ) -> [PrescribedExercise] {
        exercises.map { exercise in
            guard let targetRPE = exercise.targetRPE else { return exercise }
            let capped = PrescriptionBounds.clampRPE(targetRPE, cap: gating.rpeCap)
            guard capped != targetRPE else { return exercise }
            return replacing(exercise, targetRPE: capped)
        }
    }

    private static func trimSets(
        in exercises: inout [PrescribedExercise],
        roles: [PatternSlotRole],
        reductionNeeded: Int,
        context: SessionAutoregulationContext,
        respectMEVFloor: Bool = false
    ) -> Int {
        var remaining = reductionNeeded
        let roleSet = Set(roles)
        let orderedIndices = exercises.indices.sorted { lhs, rhs in
            let leftRole = context.exerciseRoles[exercises[lhs].exerciseID] ?? .secondary
            let rightRole = context.exerciseRoles[exercises[rhs].exerciseID] ?? .secondary
            if leftRole != rightRole {
                // Trim isolation first, primary last (RECONCILE: compounds protected at MEV floor).
                return roleRank(leftRole) < roleRank(rightRole)
            }
            return exercises[lhs].order > exercises[rhs].order
        }

        for index in orderedIndices where remaining > 0 {
            let exercise = exercises[index]
            let role = context.exerciseRoles[exercise.exerciseID] ?? .secondary
            guard roleSet.contains(role) else { continue }

            if respectMEVFloor,
               !canTrim(exercise: exercise, in: exercises, context: context) {
                continue
            }

            let trimmed = exercises[index]
            guard trimmed.targetSets > PrescriptionBounds.minSetsPerExercise else { continue }
            exercises[index] = replacing(trimmed, targetSets: trimmed.targetSets - 1)
            remaining -= 1
        }
        return remaining
    }

    private static func canTrim(
        exercise: PrescribedExercise,
        in exercises: [PrescribedExercise],
        context: SessionAutoregulationContext
    ) -> Bool {
        guard let muscle = primaryMuscle(for: exercise.exerciseID, context: context),
              let landmarks = context.mesocycleState.muscles[muscle]?.landmarks else {
            return true
        }
        let floor = dailyMEVFloor(
            landmarks: landmarks,
            remainingSessionsThisWeek: context.remainingSessionsThisWeek
        )
        let sessionSets = sessionSets(for: muscle, in: exercises, context: context)
        return sessionSets > floor
    }

    private static func minimumSessionSets(
        in exercises: [PrescribedExercise],
        context: SessionAutoregulationContext
    ) -> Int {
        var floors = 0
        var seen = Set<MuscleGroup>()
        for exercise in exercises {
            guard let muscle = primaryMuscle(for: exercise.exerciseID, context: context),
                  seen.insert(muscle).inserted,
                  let landmarks = context.mesocycleState.muscles[muscle]?.landmarks else {
                continue
            }
            floors += dailyMEVFloor(
                landmarks: landmarks,
                remainingSessionsThisWeek: context.remainingSessionsThisWeek
            )
        }
        return max(PrescriptionBounds.minSetsPerExercise, floors)
    }

    private static func dailyMEVFloor(
        landmarks: VolumeLandmarks,
        remainingSessionsThisWeek: Int
    ) -> Int {
        max(1, Int(ceil(Double(landmarks.mev) / Double(max(1, remainingSessionsThisWeek)))))
    }

    private static func sessionSets(
        for muscle: MuscleGroup,
        in exercises: [PrescribedExercise],
        context: SessionAutoregulationContext
    ) -> Int {
        exercises.reduce(0) { partial, exercise in
            guard primaryMuscle(for: exercise.exerciseID, context: context) == muscle else {
                return partial
            }
            return partial + exercise.targetSets
        }
    }

    private static func primaryMuscle(
        for exerciseID: String,
        context: SessionAutoregulationContext
    ) -> MuscleGroup? {
        context.muscleMaps[exerciseID]?.contributions
            .max(by: { $0.fraction < $1.fraction })?
            .muscle
    }

    private static func convertToTechnique(
        _ exercises: [PrescribedExercise],
        rpe: Double
    ) -> [PrescribedExercise] {
        exercises.map { exercise in
            replacing(exercise, targetRPE: PrescriptionBounds.clampRPE(rpe))
        }
    }

    private static func totalSets(in exercises: [PrescribedExercise]) -> Int {
        exercises.reduce(0) { $0 + $1.targetSets }
    }

    private static func roleRank(_ role: PatternSlotRole) -> Int {
        switch role {
        case .isolation: 0
        case .secondary: 1
        case .primary: 2
        }
    }

    private static func replacing(
        _ exercise: PrescribedExercise,
        targetSets: Int? = nil,
        targetRPE: Double? = nil
    ) -> PrescribedExercise {
        PrescribedExercise(
            id: exercise.id,
            exerciseID: exercise.exerciseID,
            order: exercise.order,
            targetSets: targetSets ?? exercise.targetSets,
            warmupSets: exercise.warmupSets,
            targetRepMin: exercise.targetRepMin,
            targetRepMax: exercise.targetRepMax,
            targetMass: exercise.targetMass,
            targetRPE: targetRPE ?? exercise.targetRPE,
            rationale: exercise.rationale,
            evidenceIDs: exercise.evidenceIDs
        )
    }
}
