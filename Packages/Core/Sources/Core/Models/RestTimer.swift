import Foundation

/// Timestamp-projected rest countdown derived from persisted `ends_at`, not a running timer.
public struct RestTimer: Sendable, Hashable, Identifiable {
    public let id: String
    public let sessionExerciseID: String?
    public let sourceSetEntryID: String?
    public let phase: RestTimerPhase
    public let startedAt: Date?
    public let endsAt: Date?
    public let defaultDurationSeconds: Int

    public init(
        id: String,
        sessionExerciseID: String? = nil,
        sourceSetEntryID: String? = nil,
        phase: RestTimerPhase,
        startedAt: Date? = nil,
        endsAt: Date? = nil,
        defaultDurationSeconds: Int = 0
    ) {
        self.id = id
        self.sessionExerciseID = sessionExerciseID
        self.sourceSetEntryID = sourceSetEntryID
        self.phase = phase
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.defaultDurationSeconds = defaultDurationSeconds
    }

    public var isActive: Bool {
        phase == .running || phase == .paused
    }

    public func remainingSeconds(at now: Date) -> Int? {
        guard phase == .running, let endsAt else { return nil }
        return max(0, Int(endsAt.timeIntervalSince(now).rounded(.down)))
    }

    public func hasExpired(at now: Date) -> Bool {
        guard phase == .running, let endsAt else { return false }
        return endsAt <= now
    }
}

public struct SetLogUpdate: Sendable, Hashable {
    public let mass: Mass?
    public let reps: Int?
    public let distanceKilometers: Double?
    public let durationSeconds: Int?
    public let rpe: Double?
    public let rir: Double?

    public init(
        mass: Mass? = nil,
        reps: Int? = nil,
        distanceKilometers: Double? = nil,
        durationSeconds: Int? = nil,
        rpe: Double? = nil,
        rir: Double? = nil
    ) {
        self.mass = mass
        self.reps = reps
        self.distanceKilometers = distanceKilometers
        self.durationSeconds = durationSeconds
        self.rpe = rpe
        self.rir = rir
    }
}

public struct ActiveSessionSnapshot: Sendable, Hashable {
    public let session: WorkoutSessionDraft
    public let recoveryState: ActiveWorkoutRecoveryState
    public let restTimer: RestTimer?

    public init(
        session: WorkoutSessionDraft,
        recoveryState: ActiveWorkoutRecoveryState,
        restTimer: RestTimer? = nil
    ) {
        self.session = session
        self.recoveryState = recoveryState
        self.restTimer = restTimer
    }

    /// True once the athlete has logged work or used the rest timer beyond its idle shell.
    public var hasMeaningfulProgress: Bool {
        if session.hasLoggedWork {
            return true
        }
        guard let restTimer else { return false }
        return restTimer.phase != .idle
    }
}

public enum ActiveSessionRecoveryPolicy: Sendable {
    /// Drops prescription shells that were auto-started but never progressed (e.g. dev reinstall).
    public static func shouldAbandonUntouchedPrescription(_ snapshot: ActiveSessionSnapshot) -> Bool {
        snapshot.session.source == .prescription && !snapshot.hasMeaningfulProgress
    }
}
