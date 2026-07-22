import Core
import Foundation
import Testing
@testable import Persistence

@Suite("Active session engine")
struct ActiveSessionEngineTests {
    private let benchPressID = "exercise-bench-press"

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

    @Test("idle and completed timers expose no remaining seconds")
    func inactiveTimersHaveNoRemaining() {
        let timer = RestTimer(id: "timer-1", phase: .completed, endsAt: Date())
        #expect(timer.remainingSeconds(at: Date()) == nil)
    }
}
