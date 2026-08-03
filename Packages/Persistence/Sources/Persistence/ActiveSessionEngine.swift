import Core
import Foundation

public actor ActiveSessionEngine {
    private let repository: ActiveSessionRepository
    private let clock: any Clock

    public init(repository: ActiveSessionRepository, clock: any Clock = SystemClock()) {
        self.repository = repository
        self.clock = clock
    }

    public func recover() throws -> ActiveSessionSnapshot? {
        let now = clock.now()
        if let snapshot = try repository.fetchActiveSnapshot(at: now) {
            try repository.completeExpiredRestTimers(sessionID: snapshot.session.id, at: now)
        }
        return try repository.fetchActiveSnapshot(at: now)
    }

    public func start(title: String? = nil) throws -> ActiveSessionSnapshot {
        let startedAt = clock.now()
        _ = try repository.startSession(title: title, startedAt: startedAt)
        guard let snapshot = try repository.fetchActiveSnapshot(at: startedAt) else {
            throw PersistenceError.recordNotFound("active session after start")
        }
        return snapshot
    }

    public func startFromTemplate(_ template: WorkoutTemplateDraft) throws -> ActiveSessionSnapshot {
        let startedAt = clock.now()
        _ = try repository.startSessionFromTemplate(template: template, startedAt: startedAt)
        guard let snapshot = try repository.fetchActiveSnapshot(at: startedAt) else {
            throw PersistenceError.recordNotFound("active session after template start")
        }
        return snapshot
    }

    public func startFromPrescription(_ prescription: SessionPrescription) throws -> ActiveSessionSnapshot {
        let startedAt = clock.now()
        _ = try repository.startSessionFromPrescription(prescription, startedAt: startedAt)
        guard let snapshot = try repository.fetchActiveSnapshot(at: startedAt) else {
            throw PersistenceError.recordNotFound("active session after prescription start")
        }
        return snapshot
    }

    public func startFromImport(_ plan: ImportedWorkoutPlan) throws -> ActiveSessionSnapshot {
        let startedAt = clock.now()
        _ = try repository.startSessionFromImport(plan, startedAt: startedAt)
        guard let snapshot = try repository.fetchActiveSnapshot(at: startedAt) else {
            throw PersistenceError.recordNotFound("active session after import start")
        }
        return snapshot
    }

    public func logSet(setID: String, update: SetLogUpdate) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        try repository.logSet(setID: setID, update: update, timestamp: now)
        return try requireSnapshot(at: now)
    }

    public func updateSetType(setID: String, setType: SetType) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        try repository.updateSetType(setID: setID, setType: setType, timestamp: now)
        return try requireSnapshot(at: now)
    }

    public func completeSet(sessionExerciseID: String, setID: String) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.completeSet(
            sessionID: snapshot.session.id,
            sessionExerciseID: sessionExerciseID,
            setID: setID,
            completedAt: now
        )
        return try requireSnapshot(at: now)
    }

    public func uncompleteSet(sessionExerciseID: String, setID: String) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.uncompleteSet(
            sessionID: snapshot.session.id,
            sessionExerciseID: sessionExerciseID,
            setID: setID,
            timestamp: now
        )
        return try requireSnapshot(at: now)
    }

    public func addExercise(exerciseID: String, defaultSetCount: Int = 3, defaultRestSeconds: Int = 90) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        _ = try repository.addExercise(
            sessionID: snapshot.session.id,
            exerciseID: exerciseID,
            defaultSetCount: defaultSetCount,
            defaultRestSeconds: defaultRestSeconds,
            timestamp: now
        )
        return try requireSnapshot(at: now)
    }

    public func removeExercise(sessionExerciseID: String) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.removeExercise(
            sessionID: snapshot.session.id,
            sessionExerciseID: sessionExerciseID,
            timestamp: now
        )
        return try requireSnapshot(at: now)
    }

    public func skipRest() throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.skipRestTimer(sessionID: snapshot.session.id, timestamp: now)
        return try requireSnapshot(at: now)
    }

    public func startManualRestTimer(durationSeconds: Int) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        let sessionExerciseID = snapshot.session.exercises.first { exercise in
            exercise.sets.contains { $0.status != .completed }
        }?.id
        try repository.startManualRestTimer(
            sessionID: snapshot.session.id,
            sessionExerciseID: sessionExerciseID,
            durationSeconds: durationSeconds,
            startedAt: now
        )
        return try requireSnapshot(at: now)
    }

    public func finish() throws -> String? {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        let sessionID = snapshot.session.id
        try repository.completeExpiredRestTimers(sessionID: sessionID, at: now)
        try repository.finishSession(sessionID: sessionID, endedAt: now)
        return sessionID
    }

    public func discard() throws {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.discardSession(sessionID: snapshot.session.id, endedAt: now)
    }

    public func restTimerProjection(at instant: Date? = nil) throws -> RestTimer? {
        let now = instant ?? clock.now()
        if let snapshot = try repository.fetchActiveSnapshot(at: now) {
            try repository.completeExpiredRestTimers(sessionID: snapshot.session.id, at: now)
        }
        return try repository.fetchActiveSnapshot(at: now)?.restTimer
    }

    public func remainingRestSeconds(at instant: Date? = nil) throws -> Int? {
        let now = instant ?? clock.now()
        guard let timer = try restTimerProjection(at: now) else { return nil }
        return timer.remainingSeconds(at: now)
    }

    public func syncFromPrescription(_ prescription: SessionPrescription) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.syncFromPrescription(
            sessionID: snapshot.session.id,
            prescription: prescription,
            timestamp: now
        )
        return try requireSnapshot(at: now)
    }

    public func adjustExerciseSetCount(
        sessionExerciseID: String,
        targetSetCount: Int
    ) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.adjustExerciseSetCount(
            sessionID: snapshot.session.id,
            sessionExerciseID: sessionExerciseID,
            targetSetCount: targetSetCount,
            timestamp: now
        )
        return try requireSnapshot(at: now)
    }

    public func restoreExerciseLayout(_ exercises: [WorkoutSessionExerciseDraft]) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.restoreExerciseLayout(
            sessionID: snapshot.session.id,
            exercises: exercises,
            timestamp: now
        )
        return try requireSnapshot(at: now)
    }

    public func updateSessionNotes(_ notes: String?) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.updateSessionNotes(
            sessionID: snapshot.session.id,
            notes: notes,
            timestamp: now
        )
        return try requireSnapshot(at: now)
    }

    public func reorderExercises(orderedSessionExerciseIDs: [String]) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.reorderExercises(
            sessionID: snapshot.session.id,
            orderedSessionExerciseIDs: orderedSessionExerciseIDs,
            timestamp: now
        )
        return try requireSnapshot(at: now)
    }

    public func adjustRestTimer(deltaSeconds: Int) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.adjustRestTimer(
            sessionID: snapshot.session.id,
            deltaSeconds: deltaSeconds,
            timestamp: now
        )
        return try requireSnapshot(at: now)
    }

    public func updateExerciseRest(sessionExerciseID: String, seconds: Int) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        try repository.updateExerciseRest(
            sessionID: snapshot.session.id,
            sessionExerciseID: sessionExerciseID,
            seconds: seconds,
            timestamp: now
        )
        return try requireSnapshot(at: now)
    }

    private func requireSnapshot(at now: Date) throws -> ActiveSessionSnapshot {
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        return snapshot
    }
}
