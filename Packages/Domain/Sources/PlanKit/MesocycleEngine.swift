import Foundation

enum MesocycleEngine {
    /// Fraction of peak volume prescribed during a deload week.
    static let deloadVolumeFraction = 0.5
    /// Global clamp for V_base historical seeding (research Thread 2).
    static let vBaseClampMin = 8.0
    static let vBaseClampMax = 15.0

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
        experience: TrainingExperience,
        historicalWeeklyHardSets: Double? = nil
    ) -> VolumeLandmarks {
        let base = baseLandmarks[muscle] ?? (6, 16)
        let scale = experienceScale(experience)
        var mev = max(2, Int((Double(base.mev) * scale).rounded()))
        var mrv = max(mev, Int((Double(base.mrv) * scale).rounded()))

        if let historical = historicalWeeklyHardSets, historical > 0 {
            let clamped = min(vBaseClampMax, max(vBaseClampMin, historical))
            let seededMEV = max(2, Int((clamped * 0.75).rounded()))
            let seededMRV = max(seededMEV + 2, Int((clamped * 1.15).rounded()))
            mev = max(mev, seededMEV)
            mrv = max(mrv, seededMRV)
            mrv = min(mrv, Int((Double(base.mrv) * scale * 1.2).rounded()))
        }

        return VolumeLandmarks(mev: mev, mrv: mrv)
    }

    /// Absolute range adaptation may move a muscle's landmarks within.
    ///
    /// Refinement runs once per block and can add up to two sets to MRV each time. Without a
    /// hard ceiling a lifter who keeps reporting good tolerance ratchets upward forever and
    /// the engine eventually prescribes volume no one recovers from.
    struct LandmarkBounds: Sendable, Hashable {
        let minMEV: Int
        let maxMRV: Int

        static let permissive = LandmarkBounds(minMEV: 2, maxMRV: 40)

        static func forMuscle(_ muscle: MuscleGroup, experience: TrainingExperience) -> LandmarkBounds {
            let base = baseLandmarks[muscle] ?? (6, 16)
            let scale = experienceScale(experience)
            let ceiling = max(12, Int((Double(base.mrv) * scale * mrvAdaptationHeadroom).rounded()))
            return LandmarkBounds(minMEV: 2, maxMRV: ceiling)
        }
    }

    /// How far above the seeded MRV a well-recovering athlete may adapt.
    static let mrvAdaptationHeadroom = 1.5

    static func experienceScale(_ experience: TrainingExperience) -> Double {
        switch experience {
        case .novice: 0.85
        case .intermediate: 1.0
        case .advanced: 1.1
        }
    }

    static func refineLandmarks(
        _ landmarks: VolumeLandmarks,
        signals: ToleranceSignals,
        bounds: LandmarkBounds = .permissive
    ) -> VolumeLandmarks {
        var mev = landmarks.mev
        var mrv = landmarks.mrv

        if signals.performanceTrend == .declining {
            mrv -= 2
            mev = max(2, mev - 1)
        } else if signals.performanceTrend == .improving {
            if let rir = signals.averageRIR, rir >= 2 {
                mrv += 1
                if rir >= 3 {
                    mev += 1
                }
            }
        }

        if let soreness = signals.sorenessRating {
            if soreness >= 7 {
                mrv -= 1
                mev = max(2, mev - 1)
            } else if soreness <= 2, signals.performanceTrend == .improving {
                mev += 1
            }
        }

        if let rir = signals.averageRIR {
            if rir < 1 {
                mrv -= 1
            } else if rir > 1.0, signals.performanceTrend != .declining {
                mrv += 1
            }
        }

        mrv = min(mrv, landmarks.mrv + 2)
        mrv = min(mrv, bounds.maxMRV)
        mev = max(bounds.minMEV, min(mev, mrv - 1))
        mrv = max(mev + 1, mrv)
        return VolumeLandmarks(mev: mev, mrv: mrv)
    }

    /// Mid-block reseed when profile changes: preserve relative position between MEV and MRV.
    static func reseedLandmarks(
        current: VolumeLandmarks,
        newSeed: VolumeLandmarks
    ) -> VolumeLandmarks {
        guard current.mrv > 0 else { return newSeed }
        let ratio = Double(newSeed.mrv) / Double(current.mrv)
        var mev = Int((Double(current.mev) * ratio).rounded())
        var mrv = Int((Double(current.mrv) * ratio).rounded())
        mev = max(newSeed.mev, min(mev, newSeed.mrv - 1))
        mrv = max(mev + 1, min(mrv, newSeed.mrv))
        return VolumeLandmarks(mev: mev, mrv: mrv)
    }

    static func weeklyHardSetTarget(for muscleState: MuscleMesocycleState) -> Int {
        let landmarks = muscleState.landmarks
        switch muscleState.phase {
        case .deload:
            return deloadWeeklyTarget(landmarks: landmarks, blockLength: muscleState.blockLengthWeeks)
        case .accumulating:
            return accumulatingTarget(
                week: muscleState.currentWeek,
                landmarks: landmarks,
                blockLength: muscleState.blockLengthWeeks
            )
        }
    }

    /// Scheduled deload: max(MEV, round(0.5 * peak week)).
    static func deloadWeeklyTarget(landmarks: VolumeLandmarks, blockLength: Int) -> Int {
        let peak = accumulatingTarget(
            week: blockLength - 1,
            landmarks: landmarks,
            blockLength: blockLength
        )
        let reduced = Int((Double(peak) * deloadVolumeFraction).rounded())
        return max(landmarks.mev, reduced)
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
        blockLengthWeeks: Int = 5,
        historicalWeeklyHardSets: [MuscleGroup: Double] = [:]
    ) -> MesocycleState {
        var state = MesocycleState()
        for muscle in muscles {
            let landmarks = seedLandmarks(
                muscle: muscle,
                experience: experience,
                historicalWeeklyHardSets: historicalWeeklyHardSets[muscle]
            )
            state.muscles[muscle] = MuscleMesocycleState(
                landmarks: landmarks,
                blockLengthWeeks: blockLengthWeeks
            )
        }
        return state
    }

    static func advanceWeek(
        _ state: MesocycleState,
        toleranceByMuscle: [MuscleGroup: ToleranceSignals] = [:],
        experience: TrainingExperience = .intermediate,
        historicalWeeklyHardSets: [MuscleGroup: Double] = [:]
    ) -> MesocycleState {
        var next = state
        for (muscle, muscleState) in state.muscles {
            if muscleState.phase == .deload {
                let signals = toleranceByMuscle[muscle] ?? ToleranceSignals()
                var landmarks = refineLandmarks(
                    muscleState.landmarks,
                    signals: signals,
                    bounds: .forMuscle(muscle, experience: experience)
                )
                if let historical = historicalWeeklyHardSets[muscle] {
                    let reseeded = seedLandmarks(
                        muscle: muscle,
                        experience: experience,
                        historicalWeeklyHardSets: historical
                    )
                    landmarks = reseedLandmarks(current: landmarks, newSeed: reseeded)
                }
                next.muscles[muscle] = MuscleMesocycleState(
                    landmarks: landmarks,
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
