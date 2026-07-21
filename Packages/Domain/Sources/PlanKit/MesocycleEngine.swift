import Foundation

enum MesocycleEngine {
    /// Fraction of peak volume prescribed during a deload week.
    static let deloadVolumeFraction = 0.5

    /// Base novice MEV/MRV pairs per muscle before experience scaling.
    static let baseLandmarks: [MuscleGroup: (mev: Int, mrv: Int)] = [
        .chest: (8, 18),
        .back: (8, 20),
        .shoulders: (8, 18),
        .biceps: (6, 16),
        .triceps: (6, 16),
        .quads: (8, 20),
        .hamstrings: (6, 16),
        .glutes: (6, 16),
        .calves: (6, 14),
        .abs: (4, 12)
    ]

    static func seedLandmarks(
        muscle: MuscleGroup,
        experience: TrainingExperience
    ) -> VolumeLandmarks {
        let base = baseLandmarks[muscle] ?? (6, 16)
        let scale: Double = switch experience {
        case .novice: 0.85
        case .intermediate: 1.0
        case .advanced: 1.1
        }
        let mev = max(2, Int((Double(base.mev) * scale).rounded()))
        let mrv = max(mev, Int((Double(base.mrv) * scale).rounded()))
        return VolumeLandmarks(mev: mev, mrv: mrv)
    }

    static func refineLandmarks(
        _ landmarks: VolumeLandmarks,
        signals: ToleranceSignals
    ) -> VolumeLandmarks {
        var mrv = landmarks.mrv

        if signals.performanceTrend == .declining {
            mrv -= 2
        } else if signals.performanceTrend == .improving {
            if let rir = signals.averageRIR, rir >= 2 {
                mrv += 1
            }
        }

        if let soreness = signals.sorenessRating, soreness >= 7 {
            mrv -= 1
        }

        if let rir = signals.averageRIR, rir < 1 {
            mrv -= 1
        }

        mrv = min(mrv, landmarks.mrv + 2)
        mrv = max(landmarks.mev + 1, mrv)
        return VolumeLandmarks(mev: landmarks.mev, mrv: mrv)
    }

    static func weeklyHardSetTarget(for muscleState: MuscleMesocycleState) -> Int {
        let landmarks = muscleState.landmarks
        switch muscleState.phase {
        case .deload:
            let peak = accumulatingTarget(
                week: muscleState.blockLengthWeeks - 1,
                landmarks: landmarks,
                blockLength: muscleState.blockLengthWeeks
            )
            let reduced = Int((Double(peak) * deloadVolumeFraction).rounded())
            return max(landmarks.mev, reduced)
        case .accumulating:
            return accumulatingTarget(
                week: muscleState.currentWeek,
                landmarks: landmarks,
                blockLength: muscleState.blockLengthWeeks
            )
        }
    }

    static func accumulatingTarget(
        week: Int,
        landmarks: VolumeLandmarks,
        blockLength: Int
    ) -> Int {
        let rampWeeks = blockLength - 1
        guard rampWeeks > 0 else { return landmarks.mev }
        if rampWeeks == 1 {
            return landmarks.mev
        }
        let clampedWeek = min(max(week, 1), rampWeeks)
        let progress = Double(clampedWeek - 1) / Double(rampWeeks - 1)
        let value = Double(landmarks.mev) + progress * Double(landmarks.mrv - landmarks.mev)
        return min(landmarks.mrv, max(landmarks.mev, Int(value.rounded())))
    }

    static func makeInitialState(
        muscles: [MuscleGroup],
        experience: TrainingExperience,
        blockLengthWeeks: Int = 5
    ) -> MesocycleState {
        var state = MesocycleState()
        for muscle in muscles {
            let landmarks = seedLandmarks(muscle: muscle, experience: experience)
            state.muscles[muscle] = MuscleMesocycleState(
                landmarks: landmarks,
                blockLengthWeeks: blockLengthWeeks
            )
        }
        return state
    }

    static func advanceWeek(
        _ state: MesocycleState,
        toleranceByMuscle: [MuscleGroup: ToleranceSignals] = [:]
    ) -> MesocycleState {
        var next = state
        for (muscle, muscleState) in state.muscles {
            if muscleState.phase == .deload {
                let signals = toleranceByMuscle[muscle] ?? ToleranceSignals()
                let refined = refineLandmarks(muscleState.landmarks, signals: signals)
                next.muscles[muscle] = MuscleMesocycleState(
                    landmarks: refined,
                    blockLengthWeeks: muscleState.blockLengthWeeks,
                    currentWeek: 1
                )
            } else {
                var updated = muscleState
                updated.currentWeek += 1
                next.muscles[muscle] = updated
            }
        }
        return next
    }
}
