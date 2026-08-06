import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Volume ruler hard-set gates")
struct VolumeRulerHardSetGateTests {
    private func workingSet(
        exerciseID: String = "bench",
        kg: Double = 80,
        reps: Int = 10,
        rir: Int? = 2,
        setType: SetType = .normal
    ) -> LoggedSet {
        LoggedSet(
            exerciseID: exerciseID,
            sequence: 1,
            mass: Mass(kilograms: kg),
            reps: reps,
            rir: rir,
            completedAt: Date(),
            setType: setType
        )
    }

    @Test("proximity to failure grades credit continuously instead of cutting off")
    func rirGradient() {
        // Robinson et al. (2024): hypertrophy rises continuously as RIR falls, so credit
        // must taper rather than switch off between RIR 4 and RIR 5.
        #expect(PlanKit.stimulusCredit(workingSet(rir: 0)) == 1.0)
        #expect(PlanKit.stimulusCredit(workingSet(rir: 2)) == 1.0)
        #expect(PlanKit.stimulusCredit(workingSet(rir: 3)) == 0.9)
        #expect(PlanKit.stimulusCredit(workingSet(rir: 4)) == 0.8)
        #expect(PlanKit.stimulusCredit(workingSet(rir: 5)) == 0.5)
        #expect(PlanKit.stimulusCredit(workingSet(rir: 6)) == 0)
    }

    @Test("credit decreases monotonically as sets get easier")
    func rirMonotonic() {
        let credits = (0 ... 8).map { PlanKit.stimulusCredit(workingSet(rir: $0)) }
        #expect(zip(credits, credits.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test("reps outside the hypertrophy band earn partial, not zero, credit")
    func repBandGrading() {
        #expect(PlanKit.stimulusCredit(workingSet(reps: 4)) == 0.5)
        #expect(PlanKit.stimulusCredit(workingSet(reps: 31)) == 0.5)
        #expect(PlanKit.stimulusCredit(workingSet(reps: 8)) == 1.0)
    }

    @Test("load floor excludes warmup-intensity work but heavy work has no ceiling")
    func loadFloorOnly() {
        let e1rm = Mass(kilograms: 100)
        let context = HardSetEvaluationContext(estimatedOneRepMaxByExercise: ["bench": e1rm])
        #expect(PlanKit.stimulusCredit(workingSet(kg: 20, reps: 10), context: context) == 0)
        #expect(PlanKit.stimulusCredit(workingSet(kg: 70, reps: 10), context: context) == 1.0)
        // A near-maximal set is still a real stimulus; the rep band already discounts it.
        #expect(PlanKit.stimulusCredit(workingSet(kg: 95, reps: 3), context: context) == 0.5)
    }

    @Test("fatigue is tracked separately from stimulus and rises with effort")
    func splitLedger() {
        let hard = PlanKit.ledgerCredit(workingSet(reps: 10, rir: 0))
        let easy = PlanKit.ledgerCredit(workingSet(reps: 10, rir: 3))
        #expect(hard.stimulus == 1.0)
        #expect(easy.stimulus == 0.9)
        // RPE 10 costs more to recover from than RPE 7 despite similar stimulus.
        #expect(hard.fatigue > easy.fatigue)
        #expect(abs(easy.fatigue - 1.0) < 0.0001)
    }

    @Test("a heavy single costs more fatigue than it returns in stimulus")
    func heavySingleExchangeRate() {
        let single = PlanKit.ledgerCredit(workingSet(reps: 3, rir: 0))
        #expect(single.fatigue > single.stimulus)
    }

    @Test("rest-pause activation and follow-up credit under intensity cap")
    func restPauseAggregation() {
        let map = ExerciseMuscleMap(
            exerciseID: "curl",
            contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1.0, tier: .primary)]
        )
        let session = WorkoutSession(
            helmDay: HelmDay(year: 2026, month: 3, day: 10),
            startedAt: Date(),
            sets: [
                LoggedSet(
                    exerciseID: "curl",
                    sequence: 1,
                    reps: 8,
                    rir: 1,
                    completedAt: Date(),
                    setType: .restPauseActivation
                ),
                LoggedSet(
                    exerciseID: "curl",
                    sequence: 2,
                    reps: 4,
                    rir: 0,
                    completedAt: Date(),
                    setType: .restPauseFollowUp
                ),
                LoggedSet(
                    exerciseID: "curl",
                    sequence: 3,
                    reps: 4,
                    rir: 0,
                    completedAt: Date(),
                    setType: .restPauseFollowUp
                )
            ]
        )
        let breakdown = HardSetAccounting.weeklyVolumeBreakdown(
            sessions: [session],
            muscleMaps: ["curl": map],
            weekStart: HelmDay(year: 2026, month: 3, day: 10)
        )
        // All mini-sets after the activation set aggregate into a single 0.5 credit,
        // so the exercise is worth 1.0 + 0.5 = 1.5 regardless of how many were logged.
        #expect(breakdown[.biceps]?.direct == 1.5)
    }

    @Test("rest-pause credit does not grow with extra mini-sets")
    func restPauseAggregateIsFlat() {
        let map = ExerciseMuscleMap(
            exerciseID: "curl",
            contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1.0, tier: .primary)]
        )
        func direct(followUps: Int) -> Double {
            var sets = [LoggedSet(
                exerciseID: "curl",
                sequence: 1,
                reps: 8,
                rir: 1,
                completedAt: Date(),
                setType: .restPauseActivation
            )]
            sets += (0 ..< followUps).map { index in
                LoggedSet(
                    exerciseID: "curl",
                    sequence: index + 2,
                    reps: 4,
                    rir: 0,
                    completedAt: Date(),
                    setType: .restPauseFollowUp
                )
            }
            let session = WorkoutSession(
                helmDay: HelmDay(year: 2026, month: 3, day: 10),
                startedAt: Date(),
                sets: sets
            )
            let breakdown = HardSetAccounting.weeklyVolumeBreakdown(
                sessions: [session],
                muscleMaps: ["curl": map],
                weekStart: HelmDay(year: 2026, month: 3, day: 10)
            )
            return breakdown[.biceps]?.direct ?? 0
        }
        #expect(direct(followUps: 1) == 1.5)
        #expect(direct(followUps: 4) == 1.5)
    }

    @Test("a lone drop row counts as the working set it stood in for")
    func orphanDropCreditedInFull() {
        let map = ExerciseMuscleMap(
            exerciseID: "curl",
            contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1.0, tier: .primary)]
        )
        let session = WorkoutSession(
            helmDay: HelmDay(year: 2026, month: 3, day: 10),
            startedAt: Date(),
            sets: [LoggedSet(
                exerciseID: "curl",
                sequence: 1,
                reps: 10,
                rir: 1,
                completedAt: Date(),
                setType: .dropSet
            )]
        )
        let breakdown = HardSetAccounting.weeklyVolumeBreakdown(
            sessions: [session],
            muscleMaps: ["curl": map],
            weekStart: HelmDay(year: 2026, month: 3, day: 10)
        )
        #expect(breakdown[.biceps]?.direct == 1.0)
    }

    @Test("orphan drop set is detectable without preceding top set")
    func orphanDropSetValidation() {
        let dropOnly = LoggedSet(
            exerciseID: "curl",
            sequence: 2,
            reps: 10,
            completedAt: Date(),
            setType: .dropSet
        )
        let withTop = LoggedSet(
            exerciseID: "curl",
            sequence: 1,
            reps: 8,
            completedAt: Date(),
            setType: .normal
        )
        #expect(PlanKit.isOrphanDropSet(dropOnly, priorSetsInExercise: []) == true)
        #expect(PlanKit.isOrphanDropSet(dropOnly, priorSetsInExercise: [withTop]) == false)
    }

    @Test("per-session stimulus saturates near the eleven-set plateau")
    func sessionSaturation() {
        // Remmert et al. (2025) put the point of undetectable outcome superiority at
        // ~11 fractional sets per session, so a 12-set session should credit close to it.
        let saturation = SessionSaturation.standard
        #expect(saturation.effective(6) == 6)
        #expect(abs(saturation.effective(12) - 10.3125) < 0.0001)
        #expect(saturation.effective(20) < 13)
    }

    @Test("saturation never returns less credit for more work")
    func saturationMonotonic() {
        let saturation = SessionSaturation.standard
        let samples = stride(from: 0.0, through: 30.0, by: 0.25).map(saturation.effective)
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test("session saturation is scoped to the session, not the exercise")
    func saturationSpansExercises() {
        // Six sets of curls followed by six of hammer curls is twelve sets of biceps.
        // Scoping the cap per exercise would let the athlete dodge it by swapping movements.
        let contributions = [ExerciseMuscleContribution(muscle: .biceps, fraction: 1.0, tier: .primary)]
        let maps = [
            "curl": ExerciseMuscleMap(exerciseID: "curl", contributions: contributions),
            "hammer": ExerciseMuscleMap(exerciseID: "hammer", contributions: contributions)
        ]
        let sets = (1 ... 12).map { index in
            LoggedSet(
                exerciseID: index <= 6 ? "curl" : "hammer",
                sequence: index,
                reps: 10,
                rir: 2,
                completedAt: Date(),
                setType: .normal
            )
        }
        let session = WorkoutSession(
            helmDay: HelmDay(year: 2026, month: 3, day: 10),
            startedAt: Date(),
            sets: sets
        )
        let breakdown = HardSetAccounting.weeklyVolumeBreakdown(
            sessions: [session],
            muscleMaps: maps,
            weekStart: HelmDay(year: 2026, month: 3, day: 10)
        )
        #expect(abs((breakdown[.biceps]?.direct ?? 0) - 10.3125) < 0.0001)
    }

    @Test("fatigue accrues without saturating")
    func fatigueDoesNotSaturate() {
        let map = ExerciseMuscleMap(
            exerciseID: "curl",
            contributions: [ExerciseMuscleContribution(muscle: .biceps, fraction: 1.0, tier: .primary)]
        )
        let sets = (1 ... 12).map { index in
            LoggedSet(
                exerciseID: "curl",
                sequence: index,
                reps: 10,
                rir: 3,
                completedAt: Date(),
                setType: .normal
            )
        }
        let session = WorkoutSession(
            helmDay: HelmDay(year: 2026, month: 3, day: 10),
            startedAt: Date(),
            sets: sets
        )
        let breakdown = HardSetAccounting.weeklyVolumeBreakdown(
            sessions: [session],
            muscleMaps: ["curl": map],
            weekStart: HelmDay(year: 2026, month: 3, day: 10)
        )
        // Twelve sets at RPE 7 cost twelve units of recovery even though stimulus plateaus.
        #expect(abs((breakdown[.biceps]?.fatigue ?? 0) - 12.0) < 0.0001)
        #expect((breakdown[.biceps]?.direct ?? 0) < 12.0)
    }

    @Test("MRV caps prescription headroom independently of the weekly stimulus target")
    func fatigueCeilingBinds() {
        let breakdown = MuscleVolumeBreakdown(direct: 4, synergist: 0, fatigue: 18)
        let stimulusOnly = HardSetAccounting.remainingWeeklyHardSets(
            weeklyTarget: 20,
            breakdown: breakdown
        )
        let withCeiling = HardSetAccounting.remainingWeeklyHardSets(
            weeklyTarget: 20,
            breakdown: breakdown,
            fatigueCeiling: 20
        )
        #expect(stimulusOnly == 16)
        #expect(withCeiling == 2)
    }
}

@Suite("Load reference")
struct LoadReferenceTests {
    private func session(day: HelmDay, at date: Date, kg: Double, reps: Int) -> WorkoutSession {
        WorkoutSession(
            helmDay: day,
            startedAt: date,
            sets: [LoggedSet(
                exerciseID: "bench",
                sequence: 1,
                mass: Mass(kilograms: kg),
                reps: reps,
                rir: 1,
                completedAt: date,
                setType: .normal
            )]
        )
    }

    @Test("a set is never graded against a reference it set itself")
    func referenceExcludesCurrentSession() {
        // With a self-referential reference the first heavy single reads as 100% of 1RM,
        // and with an upper load band that used to silently delete it from the ledger.
        let map = ExerciseMuscleMap(
            exerciseID: "bench",
            contributions: [ExerciseMuscleContribution(muscle: .chest, fraction: 1.0, tier: .primary)]
        )
        let day = HelmDay(year: 2026, month: 3, day: 10)
        let only = session(day: day, at: Date(timeIntervalSince1970: 0), kg: 100, reps: 5)
        let breakdown = HardSetAccounting.weeklyVolumeBreakdown(
            sessions: [only],
            muscleMaps: ["bench": map],
            weekStart: day
        )
        #expect(breakdown[.chest]?.direct == 1.0)
    }

    @Test("stale reference 1RM decays so honest working weight still counts")
    func referenceDecays() {
        var accumulator = LoadReferenceAccumulator()
        let logged = Date(timeIntervalSince1970: 0)
        accumulator.ingest(session(
            day: HelmDay(year: 2020, month: 1, day: 1),
            at: logged,
            kg: 100,
            reps: 1
        ))
        let fresh = accumulator.context(asOf: logged.addingTimeInterval(7 * 86_400))
            .estimatedOneRepMaxByExercise["bench"]?.kilograms ?? 0
        let stale = accumulator.context(asOf: logged.addingTimeInterval(365 * 86_400))
            .estimatedOneRepMaxByExercise["bench"]?.kilograms ?? 0
        // Inside the grace window the reference is untouched.
        #expect(abs(fresh - 103.333) < 0.01)
        #expect(stale < fresh * 0.9)
        #expect(stale > 0)
    }

    @Test("high-rep sets do not set the reference 1RM")
    func epleyRepCap() {
        var accumulator = LoadReferenceAccumulator()
        let logged = Date(timeIntervalSince1970: 0)
        accumulator.ingest(session(
            day: HelmDay(year: 2026, month: 1, day: 1),
            at: logged,
            kg: 60,
            reps: 30
        ))
        #expect(accumulator.context(asOf: logged).estimatedOneRepMaxByExercise["bench"] == nil)
    }
}

@Suite("Mesocycle research parity")
struct MesocycleResearchParityTests {
    @Test("V_base clamps historical seed between 8 and 15")
    func vBaseClamp() {
        let low = PlanKit.seedLandmarks(
            muscle: .chest,
            experience: .intermediate,
            historicalWeeklyHardSets: 3
        )
        let mid = PlanKit.seedLandmarks(
            muscle: .chest,
            experience: .intermediate,
            historicalWeeklyHardSets: 12
        )
        let high = PlanKit.seedLandmarks(
            muscle: .chest,
            experience: .intermediate,
            historicalWeeklyHardSets: 22
        )
        #expect(low.mev >= 6)
        #expect(mid.mev >= 8)
        #expect(high.mrv <= 22)
    }

    @Test("refinement adjusts MEV and MRV from tolerance signals")
    func mevMrvRefinement() {
        let landmarks = VolumeLandmarks(mev: 8, mrv: 18)
        let refined = PlanKit.refineLandmarks(
            landmarks,
            signals: ToleranceSignals(averageRIR: 3, sorenessRating: 1, performanceTrend: .improving)
        )
        #expect(refined.mrv >= landmarks.mrv)
        #expect(refined.mev >= landmarks.mev)
    }

    @Test("repeated good tolerance cannot ratchet MRV upward without bound")
    func mrvRatchetIsBounded() {
        // Refinement runs once per block and may add two sets each time. Twenty blocks of
        // glowing feedback must not end with the engine prescribing sixty sets of chest.
        let signals = ToleranceSignals(
            averageRIR: 3,
            sorenessRating: 1,
            performanceTrend: .improving
        )
        var landmarks = PlanKit.seedLandmarks(muscle: .chest, experience: .intermediate)
        for _ in 0 ..< 20 {
            landmarks = PlanKit.refineLandmarks(
                landmarks,
                signals: signals,
                muscle: .chest,
                experience: .intermediate
            )
        }
        #expect(landmarks.mrv <= 27)
        #expect(landmarks.mev < landmarks.mrv)
    }

    @Test("declining performance walks landmarks back down")
    func decliningTrendReducesVolume() {
        let signals = ToleranceSignals(
            averageRIR: 0,
            sorenessRating: 8,
            performanceTrend: .declining
        )
        let start = VolumeLandmarks(mev: 10, mrv: 20)
        let refined = PlanKit.refineLandmarks(start, signals: signals, muscle: .chest)
        #expect(refined.mrv < start.mrv)
        #expect(refined.mev < start.mev)
    }

    @Test("mid-block reseed preserves relative landmark position")
    func midBlockReseed() {
        let current = VolumeLandmarks(mev: 10, mrv: 20)
        let newSeed = VolumeLandmarks(mev: 12, mrv: 24)
        let reseeded = PlanKit.reseedLandmarks(current: current, newSeed: newSeed)
        #expect(reseeded.mev >= newSeed.mev)
        #expect(reseeded.mrv <= newSeed.mrv)
        #expect(reseeded.mrv > reseeded.mev)
    }
}
