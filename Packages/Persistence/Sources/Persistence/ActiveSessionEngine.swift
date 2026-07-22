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

    public func logSet(setID: String, update: SetLogUpdate) throws -> ActiveSessionSnapshot {
        let now = clock.now()
        try repository.logSet(setID: setID, update: update, timestamp: now)
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

    private func requireSnapshot(at now: Date) throws -> ActiveSessionSnapshot {
        guard let snapshot = try repository.fetchActiveSnapshot(at: now) else {
            throw PersistenceError.noActiveSession
        }
        return snapshot
    }
}
