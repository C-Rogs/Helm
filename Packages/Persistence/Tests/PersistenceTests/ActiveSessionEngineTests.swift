import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Active session engine")
struct ActiveSessionEngineTests {
    private let benchPressID = "exercise-bench-press"
    private let squatID = "exercise-squat"

    private func makeHarness(at instant: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws -> (
        store: PersistenceStore,
        engine: ActiveSessionEngine,
        clock: FixedClock
    ) {
        let persistence = try PersistenceStore.inMemory()
        let clock = FixedClock(instant: instant)
        let engine = ActiveSessionEngine(repository: persistence.activeSessions, clock: clock)
        return (persistence, engine, clock)
    }

    private func seedBenchPress(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: benchPressID,
            canonicalName: "bench press (barbell)",
            displayName: "Bench Press (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "chest"
        )
    }

    private func seedSquat(in store: PersistenceStore) throws {
        try store.exercises.upsert(
            id: squatID,
            canonicalName: "squat (barbell)",
            displayName: "Squat (Barbell)",
            exerciseMode: .weightReps,
            primaryMuscleGroup: "quads"
        )
    }

    @Test("kill and recover restores exact in-progress state")
    func killAndRecoverRestoresState() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let persistence = try PersistenceStore.inMemory()
        let clock = FixedClock(instant: start)
        let engine = ActiveSessionEngine(repository: persistence.activeSessions, clock: clock)
        try seedBenchPress(in: persistence)

        let started = try await engine.start(title: "Push")
        let withExercise = try await engine.addExercise(exerciseID: benchPressID, defaultRestSeconds: 75)
        let exercise = try #require(withExercise.session.exercises.first)
        let set = try #require(exercise.sets.first)

        _ = try await engine.logSet(
            setID: set.id,
            update: SetLogUpdate(mass: Mass(kilograms: 80), reps: 8, rpe: 8)
        )

        let databaseURL = await persistence.databaseURL
        let reopenedStore = try PersistenceStore.open(at: databaseURL)
        let recoveredEngine = ActiveSessionEngine(
            repository: reopenedStore.activeSessions,
            clock: FixedClock(instant: start.addingTimeInterval(30))
        )

        let recovered = try await recoveredEngine.recover()
        let snapshot = try #require(recovered)

        #expect(snapshot.session.title == "Push")
        #expect(snapshot.session.status == .active)
        #expect(snapshot.recoveryState == .active)
        #expect(snapshot.session.exercises.count == 1)
        #expect(snapshot.session.exercises[0].exerciseID == benchPressID)
        #expect(snapshot.session.exercises[0].sets.count == 3)

        let loggedSet = snapshot.session.exercises[0].sets[0]
        #expect(loggedSet.mass?.kilograms == 80)
        #expect(loggedSet.reps == 8)
        #expect(loggedSet.rpe == 8)
        #expect(loggedSet.status == .planned)
        _ = started
    }

    @Test("rest timer projection survives simulated backgrounding")
    func restTimerProjectionAcrossBackgrounding() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var clock = FixedClock(instant: start)
        let persistence = try PersistenceStore.inMemory()
        let engine = ActiveSessionEngine(repository: persistence.activeSessions, clock: clock)
        try seedBenchPress(in: persistence)

        _ = try await engine.start()
        let withExercise = try await engine.addExercise(exerciseID: benchPressID, defaultRestSeconds: 90)
        let exercise = try #require(withExercise.session.exercises.first)
        let set = try #require(exercise.sets.first)

        _ = try await engine.logSet(
            setID: set.id,
            update: SetLogUpdate(mass: Mass(kilograms: 60), reps: 10)
        )
        let afterComplete = try await engine.completeSet(sessionExerciseID: exercise.id, setID: set.id)

        let timer = try #require(afterComplete.restTimer)
        #expect(timer.phase == .running)
        #expect(timer.remainingSeconds(at: start) == 90)
        #expect(timer.remainingSeconds(at: start.addingTimeInterval(30)) == 60)
        #expect(timer.remainingSeconds(at: start.addingTimeInterval(90)) == 0)

        let atExpiry = try await engine.restTimerProjection(at: start.addingTimeInterval(89))
        #expect(atExpiry?.phase == .running)
        #expect(atExpiry?.remainingSeconds(at: start.addingTimeInterval(89)) == 1)

        clock.instant = start.addingTimeInterval(120)
        let laterEngine = ActiveSessionEngine(repository: persistence.activeSessions, clock: clock)
        let expiredProjection = try await laterEngine.restTimerProjection()
        #expect(expiredProjection == nil)

        let persisted = try await laterEngine.recover()
        #expect(persisted?.restTimer == nil)
    }

    @Test("finish writes a completed session and clears active state")
    func finishWritesCompletedSession() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var clock = FixedClock(instant: start)
        let persistence = try PersistenceStore.inMemory()
        let engine = ActiveSessionEngine(repository: persistence.activeSessions, clock: clock)
        try seedBenchPress(in: persistence)

        _ = try await engine.start(title: "Legs")
        let withExercise = try await engine.addExercise(exerciseID: benchPressID)
        let exercise = try #require(withExercise.session.exercises.first)
        let set = try #require(exercise.sets.first)

        _ = try await engine.logSet(
            setID: set.id,
            update: SetLogUpdate(mass: Mass(kilograms: 100), reps: 5)
        )
        _ = try await engine.completeSet(sessionExerciseID: exercise.id, setID: set.id)

        clock.instant = start.addingTimeInterval(600)
        let finishingEngine = ActiveSessionEngine(repository: persistence.activeSessions, clock: clock)
        try await finishingEngine.finish()

        let recovered = try await finishingEngine.recover()
        #expect(recovered == nil)

        let status = try persistence.activeSessions.sessionStatus(sessionID: withExercise.session.id)
        #expect(status == .completed)
    }

    @Test("discard removes active session without completing it")
    func discardClearsActiveSession() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (persistence, engine, _) = try makeHarness(at: start)
        try seedBenchPress(in: persistence)

        let started = try await engine.start()
        try await engine.discard()

        let recovered = try await engine.recover()
        #expect(recovered == nil)

        let status = try persistence.activeSessions.sessionStatus(sessionID: started.session.id)
        #expect(status == .discarded)
    }

    @Test("complete set starts rest timer; skip rest clears it")
    func skipRestClearsTimer() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (persistence, engine, _) = try makeHarness(at: start)
        try seedBenchPress(in: persistence)

        _ = try await engine.start()
        let withExercise = try await engine.addExercise(exerciseID: benchPressID, defaultRestSeconds: 60)
        let exercise = try #require(withExercise.session.exercises.first)
        let set = try #require(exercise.sets.first)

        _ = try await engine.completeSet(sessionExerciseID: exercise.id, setID: set.id)
        let afterSkip = try await engine.skipRest()

        #expect(afterSkip.restTimer == nil)
    }

    @Test("manual rest timer starts and replaces running auto rest")
    func manualRestTimerStartsAndReplacesAuto() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (persistence, engine, clock) = try makeHarness(at: start)
        try seedBenchPress(in: persistence)

        _ = try await engine.start()
        let withExercise = try await engine.addExercise(exerciseID: benchPressID, defaultRestSeconds: 60)
        let exercise = try #require(withExercise.session.exercises.first)
        let set = try #require(exercise.sets.first)

        _ = try await engine.completeSet(sessionExerciseID: exercise.id, setID: set.id)
        let afterManual = try await engine.startManualRestTimer(durationSeconds: 120)

        #expect(afterManual.restTimer?.phase == .running)
        #expect(afterManual.restTimer?.defaultDurationSeconds == 120)
        let remaining = try #require(afterManual.restTimer?.remainingSeconds(at: clock.now()))
        #expect(remaining == 120)

        let afterSkip = try await engine.skipRest()
        #expect(afterSkip.restTimer == nil)
    }

    @Test("uncomplete set reverts status and cancels linked rest timer")
    func uncompleteSetRevertsStatusAndClearsRestTimer() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (persistence, engine, _) = try makeHarness(at: start)
        try seedBenchPress(in: persistence)

        _ = try await engine.start()
        let withExercise = try await engine.addExercise(exerciseID: benchPressID, defaultRestSeconds: 90)
        let exercise = try #require(withExercise.session.exercises.first)
        let set = try #require(exercise.sets.first)

        _ = try await engine.logSet(
            setID: set.id,
            update: SetLogUpdate(mass: Mass(kilograms: 60), reps: 10)
        )
        let afterComplete = try await engine.completeSet(sessionExerciseID: exercise.id, setID: set.id)

        #expect(afterComplete.restTimer?.phase == .running)
        let completedSet = try #require(afterComplete.session.exercises.first?.sets.first)
        #expect(completedSet.status == .completed)

        let afterUncomplete = try await engine.uncompleteSet(sessionExerciseID: exercise.id, setID: set.id)

        #expect(afterUncomplete.restTimer == nil)
        let revertedSet = try #require(afterUncomplete.session.exercises.first?.sets.first)
        #expect(revertedSet.status == .planned)
        #expect(revertedSet.completedAt == nil)
    }

    @Test("remove exercise drops it from the active session")
    func removeExerciseUpdatesSession() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (persistence, engine, _) = try makeHarness(at: start)
        try seedBenchPress(in: persistence)

        _ = try await engine.start()
        let withExercise = try await engine.addExercise(exerciseID: benchPressID)
        let exercise = try #require(withExercise.session.exercises.first)

        let afterRemove = try await engine.removeExercise(sessionExerciseID: exercise.id)
        #expect(afterRemove.session.exercises.isEmpty)
    }

    @Test("starting a second session is rejected while one is active")
    func rejectsDuplicateActiveSession() async throws {
        let (persistence, engine, _) = try makeHarness()
        try seedBenchPress(in: persistence)

        _ = try await engine.start()
        await #expect(throws: PersistenceError.activeSessionAlreadyExists) {
            try await engine.start()
        }
    }

    @Test("prescription start pre-populates exercises, sets, and targets")
    func prescriptionStartPrePopulatesTargets() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (persistence, engine, _) = try makeHarness(at: start)
        try seedBenchPress(in: persistence)

        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 7, day: 23),
            exercises: [
                PrescribedExercise(
                    exerciseID: benchPressID,
                    order: 0,
                    targetSets: 3,
                    targetRepMin: 8,
                    targetRepMax: 8,
                    targetMass: Mass(kilograms: 80),
                    targetRPE: 8
                )
            ]
        )

        let started = try await engine.startFromPrescription(prescription)

        #expect(started.session.source == .prescription)
        #expect(started.session.title == "Today's session")
        #expect(started.session.exercises.count == 1)
        #expect(started.session.exercises[0].exerciseID == benchPressID)
        #expect(started.session.exercises[0].sets.count == 3)

        let firstSet = try #require(started.session.exercises[0].sets[0])
        #expect(firstSet.mass?.kilograms == 80)
        #expect(firstSet.reps == 8)
        #expect(firstSet.rpe == 8)
        #expect(firstSet.status == .planned)
    }

    @Test("remove then add set does not violate set_index uniqueness")
    func removeThenAddSet() async throws {
        let (persistence, engine, _) = try makeHarness()
        try seedBenchPress(in: persistence)

        _ = try await engine.start()
        let withExercise = try await engine.addExercise(exerciseID: benchPressID)
        let exercise = try #require(withExercise.session.exercises.first)
        #expect(exercise.sets.count == 3)

        let afterRemove = try await engine.adjustExerciseSetCount(
            sessionExerciseID: exercise.id,
            targetSetCount: 2
        )
        #expect(afterRemove.session.exercises.first?.sets.count == 2)

        let afterAdd = try await engine.adjustExerciseSetCount(
            sessionExerciseID: exercise.id,
            targetSetCount: 3
        )
        let sets = try #require(afterAdd.session.exercises.first?.sets)
        #expect(sets.count == 3)
        #expect(Set(sets.map(\.setIndex)).count == 3)
    }

    @Test("adjustExerciseSetCount targets working sets when warmups exist")
    func adjustSetCountIgnoresWarmupsInTarget() async throws {
        let (persistence, engine, _) = try makeHarness()
        try seedBenchPress(in: persistence)

        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 8, day: 5),
            exercises: [
                PrescribedExercise(exerciseID: benchPressID, order: 0, targetSets: 3, warmupSets: 2)
            ]
        )
        let started = try await engine.startFromPrescription(prescription)
        let exercise = try #require(started.session.exercises.first)
        #expect(exercise.sets.filter(\.setType.isWarmup).count == 2)
        #expect(exercise.sets.filter { $0.setType.countsAsPrescribedWorkingSet }.count == 3)
        #expect(exercise.sets.count == 5)

        // UI previously passed total.count-1 (=4), which grew working sets.
        // Correct path: workingCount-1 (=2).
        let afterRemove = try await engine.adjustExerciseSetCount(
            sessionExerciseID: exercise.id,
            targetSetCount: 2
        )
        let afterRemoveExercise = try #require(afterRemove.session.exercises.first)
        #expect(afterRemoveExercise.sets.filter(\.setType.isWarmup).count == 2)
        #expect(afterRemoveExercise.sets.filter { $0.setType.countsAsPrescribedWorkingSet }.count == 2)
        #expect(afterRemoveExercise.sets.count == 4)

        let afterAdd = try await engine.adjustExerciseSetCount(
            sessionExerciseID: exercise.id,
            targetSetCount: 3
        )
        let afterAddExercise = try #require(afterAdd.session.exercises.first)
        #expect(afterAddExercise.sets.filter(\.setType.isWarmup).count == 2)
        #expect(afterAddExercise.sets.filter { $0.setType.countsAsPrescribedWorkingSet }.count == 3)
        #expect(afterAddExercise.sets.count == 5)
    }

    @Test("update set type persists through snapshot")
    func updateSetTypePersists() async throws {
        let (persistence, engine, _) = try makeHarness()
        try seedBenchPress(in: persistence)

        _ = try await engine.start()
        let withExercise = try await engine.addExercise(exerciseID: benchPressID)
        let exercise = try #require(withExercise.session.exercises.first)
        let set = try #require(exercise.sets.first)

        let updated = try await engine.updateSetType(setID: set.id, setType: .warmup)
        let warmupSet = try #require(updated.session.exercises.first?.sets.first)
        #expect(warmupSet.setType == .warmup)

        let dropSet = try await engine.updateSetType(setID: set.id, setType: .dropSet)
        let typedSet = try #require(dropSet.session.exercises.first?.sets.first)
        #expect(typedSet.setType == .dropSet)
    }

    @Test("bridge ignores drop rows for targetSets and sync preserves them")
    func bridgeAndSyncPreserveDrops() async throws {
        let (persistence, engine, _) = try makeHarness()
        try seedBenchPress(in: persistence)

        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 8, day: 5),
            exercises: [
                PrescribedExercise(exerciseID: benchPressID, order: 0, targetSets: 3, warmupSets: 0)
            ]
        )
        var snapshot = try await engine.startFromPrescription(prescription)
        let exercise = try #require(snapshot.session.exercises.first)
        let lastSet = try #require(exercise.sets.last)
        snapshot = try await engine.updateSetType(setID: lastSet.id, setType: .dropSet)

        let bridged = ActiveSessionPrescriptionBridge.prescribedSession(from: snapshot)
        let bridgedBench = try #require(bridged.exercises.first)
        #expect(bridgedBench.targetSets == 2)
        #expect(bridgedBench.warmupSets == 0)

        // Sync back the bridged plan: working slots shrink, drop row must remain.
        try persistence.activeSessions.syncFromPrescription(
            sessionID: snapshot.session.id,
            prescription: bridged,
            timestamp: Date()
        )
        let refreshed = try #require(try persistence.activeSessions.fetchActiveSnapshot(at: Date()))
        let sets = try #require(refreshed.session.exercises.first?.sets)
        #expect(sets.filter { $0.setType.countsAsPrescribedWorkingSet }.count == 2)
        #expect(sets.filter { $0.setType == .dropSet }.count == 1)
    }

    @Test("sync from prescription writes a new working weight onto planned sets")
    func syncFromPrescriptionWritesPlannedLoad() async throws {
        let (persistence, engine, _) = try makeHarness()
        try seedBenchPress(in: persistence)

        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 8, day: 5),
            exercises: [
                PrescribedExercise(
                    exerciseID: benchPressID,
                    order: 0,
                    targetSets: 3,
                    warmupSets: 0,
                    targetMass: Mass(kilograms: 80)
                )
            ]
        )
        let snapshot = try await engine.startFromPrescription(prescription)
        let adjusted = SessionPrescription(
            helmDay: prescription.helmDay,
            exercises: [
                PrescribedExercise(
                    exerciseID: benchPressID,
                    order: 0,
                    targetSets: 3,
                    warmupSets: 0,
                    targetMass: Mass(kilograms: 100)
                )
            ]
        )
        try persistence.activeSessions.syncFromPrescription(
            sessionID: snapshot.session.id,
            prescription: adjusted,
            timestamp: Date()
        )

        let refreshed = try #require(try persistence.activeSessions.fetchActiveSnapshot(at: Date()))
        let working = try #require(refreshed.session.exercises.first).sets.filter {
            $0.setType.countsAsPrescribedWorkingSet
        }
        #expect(working.count == 3)
        #expect(working.allSatisfy { $0.mass?.kilograms == 100 })
    }

    @Test("sync from prescription writes a new rep target onto planned sets")
    func syncFromPrescriptionWritesPlannedReps() async throws {
        let (persistence, engine, _) = try makeHarness()
        try seedBenchPress(in: persistence)

        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 8, day: 5),
            exercises: [
                PrescribedExercise(
                    exerciseID: benchPressID,
                    order: 0,
                    targetSets: 3,
                    warmupSets: 0,
                    targetRepMin: 8,
                    targetRepMax: 8,
                    targetMass: Mass(kilograms: 80)
                )
            ]
        )
        let snapshot = try await engine.startFromPrescription(prescription)
        let adjusted = SessionPrescription(
            helmDay: prescription.helmDay,
            exercises: [
                PrescribedExercise(
                    exerciseID: benchPressID,
                    order: 0,
                    targetSets: 3,
                    warmupSets: 0,
                    targetRepMin: 10,
                    targetRepMax: 10,
                    targetMass: Mass(kilograms: 80)
                )
            ]
        )
        try persistence.activeSessions.syncFromPrescription(
            sessionID: snapshot.session.id,
            prescription: adjusted,
            timestamp: Date()
        )

        let refreshed = try #require(try persistence.activeSessions.fetchActiveSnapshot(at: Date()))
        let working = try #require(refreshed.session.exercises.first).sets.filter {
            $0.setType.countsAsPrescribedWorkingSet
        }
        #expect(working.allSatisfy { $0.reps == 10 })
        #expect(working.allSatisfy { $0.mass?.kilograms == 80 })
    }

    @Test("sync from prescription does not homogenize planned loads when target is unchanged")
    func syncFromPrescriptionKeepsMixedPlannedLoads() async throws {
        let (persistence, engine, _) = try makeHarness()
        try seedBenchPress(in: persistence)

        let prescription = SessionPrescription(
            helmDay: HelmDay(year: 2026, month: 8, day: 5),
            exercises: [
                PrescribedExercise(
                    exerciseID: benchPressID,
                    order: 0,
                    targetSets: 3,
                    warmupSets: 0,
                    targetMass: Mass(kilograms: 80)
                )
            ]
        )
        var snapshot = try await engine.startFromPrescription(prescription)
        let exercise = try #require(snapshot.session.exercises.first)
        let second = try #require(exercise.sets.dropFirst().first)
        snapshot = try await engine.logSet(
            setID: second.id,
            update: SetLogUpdate(mass: Mass(kilograms: 85), reps: 8)
        )

        let unchanged = ActiveSessionPrescriptionBridge.prescribedSession(from: snapshot)
        try persistence.activeSessions.syncFromPrescription(
            sessionID: snapshot.session.id,
            prescription: unchanged,
            timestamp: Date()
        )

        let refreshed = try #require(try persistence.activeSessions.fetchActiveSnapshot(at: Date()))
        let sets = try #require(refreshed.session.exercises.first?.sets.sorted { $0.setIndex < $1.setIndex })
        #expect(sets[0].mass?.kilograms == 80)
        #expect(sets[1].mass?.kilograms == 85)
        #expect(sets[2].mass?.kilograms == 80)
    }

    @Test("reorder exercises preserves sets on each exercise")
    func reorderExercisesPreservesSets() async throws {
        let (persistence, engine, _) = try makeHarness()
        try seedBenchPress(in: persistence)
        try seedSquat(in: persistence)

        _ = try await engine.start()
        let withBench = try await engine.addExercise(exerciseID: benchPressID)
        let benchExercise = try #require(withBench.session.exercises.first)
        let withBoth = try await engine.addExercise(exerciseID: squatID)
        let squatExercise = try #require(withBoth.session.exercises.last)

        let benchSet = try #require(benchExercise.sets.first)
        let squatSet = try #require(squatExercise.sets.first)

        _ = try await engine.logSet(
            setID: benchSet.id,
            update: SetLogUpdate(mass: Mass(kilograms: 80), reps: 8)
        )
        _ = try await engine.logSet(
            setID: squatSet.id,
            update: SetLogUpdate(mass: Mass(kilograms: 100), reps: 5)
        )

        let reordered = try await engine.reorderExercises(
            orderedSessionExerciseIDs: [squatExercise.id, benchExercise.id]
        )

        #expect(reordered.session.exercises.count == 2)
        #expect(reordered.session.exercises[0].exerciseID == squatID)
        #expect(reordered.session.exercises[1].exerciseID == benchPressID)
        #expect(reordered.session.exercises[0].sets.count == 3)
        #expect(reordered.session.exercises[1].sets.count == 3)

        let reorderedSquatSet = try #require(reordered.session.exercises[0].sets.first)
        let reorderedBenchSet = try #require(reordered.session.exercises[1].sets.first)
        #expect(reorderedSquatSet.id == squatSet.id)
        #expect(reorderedSquatSet.mass?.kilograms == 100)
        #expect(reorderedSquatSet.reps == 5)
        #expect(reorderedBenchSet.id == benchSet.id)
        #expect(reorderedBenchSet.mass?.kilograms == 80)
        #expect(reorderedBenchSet.reps == 8)
    }

    @Test("adjust rest timer clamps remaining at zero")
    func adjustRestTimerClampsAtZero() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var clock = FixedClock(instant: start)
        let persistence = try PersistenceStore.inMemory()
        let engine = ActiveSessionEngine(repository: persistence.activeSessions, clock: clock)
        try seedBenchPress(in: persistence)

        _ = try await engine.start()
        let withExercise = try await engine.addExercise(exerciseID: benchPressID, defaultRestSeconds: 90)
        let exercise = try #require(withExercise.session.exercises.first)
        let set = try #require(exercise.sets.first)

        _ = try await engine.logSet(
            setID: set.id,
            update: SetLogUpdate(mass: Mass(kilograms: 60), reps: 10)
        )
        let afterComplete = try await engine.completeSet(sessionExerciseID: exercise.id, setID: set.id)
        let timer = try #require(afterComplete.restTimer)
        #expect(timer.remainingSeconds(at: start) == 90)

        let afterExtend = try await engine.adjustRestTimer(deltaSeconds: 30)
        let extendedTimer = try #require(afterExtend.restTimer)
        #expect(extendedTimer.remainingSeconds(at: start) == 120)

        clock.instant = start.addingTimeInterval(115)
        let afterSubtract = try await engine.adjustRestTimer(deltaSeconds: -20)
        let adjustedTimer = try #require(afterSubtract.restTimer)
        #expect(adjustedTimer.remainingSeconds(at: clock.instant) == 0)
    }

    @Test("foreign session exercise id cannot delete sets via removeExercise")
    func foreignExerciseCannotDeleteSets() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (persistence, engineA, _) = try makeHarness(at: start)
        try seedBenchPress(in: persistence)
        try seedSquat(in: persistence)

        let sessionA = try await engineA.start(title: "A")
        let withA = try await engineA.addExercise(exerciseID: benchPressID)
        let exerciseA = try #require(withA.session.exercises.first)
        let setAID = try #require(exerciseA.sets.first?.id)
        _ = try await engineA.finish()

        let engineB = ActiveSessionEngine(
            repository: persistence.activeSessions,
            clock: FixedClock(instant: start.addingTimeInterval(60))
        )
        let sessionB = try await engineB.start(title: "B")
        _ = try await engineB.addExercise(exerciseID: squatID)

        #expect(throws: PersistenceError.recordNotFound("session exercise \(exerciseA.id)")) {
            try persistence.activeSessions.removeExercise(
                sessionID: sessionB.session.id,
                sessionExerciseID: exerciseA.id,
                timestamp: start.addingTimeInterval(60)
            )
        }

        // Finished session A's sets must remain undeleted.
        let draft = try #require(try persistence.workoutSessions.fetch(id: sessionA.session.id))
        let stillThere = try #require(draft.exercises.first { $0.id == exerciseA.id })
        #expect(stillThere.sets.contains { $0.id == setAID })
        #expect(!stillThere.sets.isEmpty)
    }

    @Test("mismatched set and exercise ids do not start a rest timer")
    func mismatchedCompleteSetDoesNotStartTimer() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let (persistence, engine, _) = try makeHarness(at: start)
        try seedBenchPress(in: persistence)
        try seedSquat(in: persistence)

        _ = try await engine.start()
        let withBench = try await engine.addExercise(exerciseID: benchPressID)
        let withBoth = try await engine.addExercise(exerciseID: squatID)
        let bench = try #require(withBench.session.exercises.first)
        let squat = try #require(withBoth.session.exercises.last)
        let squatSet = try #require(squat.sets.first)

        await #expect(throws: PersistenceError.self) {
            try await engine.completeSet(sessionExerciseID: bench.id, setID: squatSet.id)
        }

        let snapshot = try #require(try await engine.recover())
        #expect(snapshot.restTimer == nil)
        let squatAfter = try #require(snapshot.session.exercises.first { $0.id == squat.id })
        #expect(squatAfter.sets.first?.status != .completed)
    }
}

@Suite("Rest timer projection")
struct RestTimerProjectionTests {
    @Test("remaining seconds clamps at zero")
    func remainingSecondsClampsAtZero() {
        let endsAt = Date(timeIntervalSince1970: 100)
        let timer = RestTimer(
            id: "timer-1",
            phase: .running,
            startedAt: Date(timeIntervalSince1970: 0),
            endsAt: endsAt,
            defaultDurationSeconds: 100
        )

        #expect(timer.remainingSeconds(at: Date(timeIntervalSince1970: 40)) == 60)
        #expect(timer.remainingSeconds(at: Date(timeIntervalSince1970: 100)) == 0)
        #expect(timer.remainingSeconds(at: Date(timeIntervalSince1970: 150)) == 0)
    }

    @Test("display zero does not mean expired while endsAt is still ahead")
    func remainingZeroBeforeExpiry() {
        let endsAt = Date(timeIntervalSince1970: 100.4)
        let timer = RestTimer(
            id: "timer-1",
            phase: .running,
            startedAt: Date(timeIntervalSince1970: 0),
            endsAt: endsAt,
            defaultDurationSeconds: 100
        )
        let justBefore = Date(timeIntervalSince1970: 100.1)
        #expect(timer.remainingSeconds(at: justBefore) == 0)
        #expect(!timer.hasExpired(at: justBefore))
        #expect(timer.hasExpired(at: Date(timeIntervalSince1970: 100.4)))
    }

    @Test("idle and completed timers expose no remaining seconds")
    func inactiveTimersHaveNoRemaining() {
        let timer = RestTimer(id: "timer-1", phase: .completed, endsAt: Date())
        #expect(timer.remainingSeconds(at: Date()) == nil)
    }
}
