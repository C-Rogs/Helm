import Core
import Foundation
import GRDB

public struct ActiveSessionRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func fetchActiveSnapshot(at now: Date) throws -> ActiveSessionSnapshot? {
        try pool.read { db in
            guard let header = try Row.fetchOne(
                db,
                sql: """
                    SELECT ws.id, ws.title, ws.started_at, ws.status, ws.source,
                           aws.recovery_state
                    FROM workout_session ws
                    JOIN active_workout_state aws ON aws.workout_session_id = ws.id
                    WHERE ws.status = 'active' AND ws.deleted_at IS NULL
                    ORDER BY datetime(ws.started_at) DESC
                    LIMIT 1
                    """
            ) else {
                return nil
            }

            let sessionID: String = header["id"]
            let startedAt = try ISO8601Coding.date(from: header["started_at"] as String)
            let recoveryState = ActiveWorkoutRecoveryState(rawValue: header["recovery_state"] as String) ?? .active
            let source = WorkoutSessionSource(rawValue: header["source"] as String) ?? .manual
            let title: String? = header["title"]

            let exercises = try Self.fetchExercises(db: db, sessionID: sessionID)
            let restTimer = try Self.fetchRunningRestTimer(db: db, sessionID: sessionID, now: now)

            let draft = WorkoutSessionDraft(
                id: sessionID,
                title: title,
                startedAt: startedAt,
                endedAt: nil,
                status: .active,
                source: source,
                exercises: exercises
            )
            return ActiveSessionSnapshot(session: draft, recoveryState: recoveryState, restTimer: restTimer)
        }
    }

    public func startSession(title: String?, startedAt: Date) throws -> String {
        let sessionID = UUID().uuidString
        let nowString = ISO8601Coding.string(from: startedAt)
        try pool.write { db in
            try Self.assertNoActiveSession(db: db)
            try db.execute(
                sql: """
                    INSERT INTO workout_session (
                        id, title, started_at, ended_at, status, source,
                        total_volume_kg_cache, total_set_count_cache, total_rep_count_cache,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, NULL, 'active', 'manual', 0, 0, 0, ?, ?)
                    """,
                arguments: [sessionID, title, nowString, nowString, nowString]
            )
            try Self.insertActiveState(db: db, sessionID: sessionID, now: nowString)
        }
        return sessionID
    }

    public func logSet(setID: String, update: SetLogUpdate, timestamp: Date) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            guard try Self.activeSessionID(forSetID: setID, db: db) != nil else {
                throw PersistenceError.recordNotFound("set \(setID)")
            }
            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET weight_kg = ?, reps = ?, distance_km = ?, duration_seconds = ?,
                        rpe = ?, rir = ?, updated_at = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [
                    update.mass?.kilograms,
                    update.reps,
                    update.distanceKilometers,
                    update.durationSeconds,
                    update.rpe,
                    update.rir,
                    now,
                    setID
                ]
            )
            if let sessionID = try Self.activeSessionID(forSetID: setID, db: db) {
                try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
            }
        }
    }

    public func completeSet(
        sessionID: String,
        sessionExerciseID: String,
        setID: String,
        completedAt: Date
    ) throws {
        let now = ISO8601Coding.string(from: completedAt)
        try pool.write { db in
            let before = try Row.fetchOne(
                db,
                sql: "SELECT status FROM set_entry WHERE id = ?",
                arguments: [setID]
            )
            let wasCompleted = (before?["status"] as String?) == SetStatus.completed.rawValue

            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET logged_exercise_id = COALESCE(
                            logged_exercise_id,
                            (SELECT exercise_id FROM workout_session_exercise WHERE id = ?)
                        ),
                        status = 'completed', completed_at = ?, updated_at = ?
                    WHERE id = ? AND workout_session_exercise_id = ? AND deleted_at IS NULL
                    """,
                arguments: [sessionExerciseID, now, now, setID, sessionExerciseID]
            )

            if !wasCompleted {
                try Self.skipRunningRestTimers(db: db, sessionID: sessionID, now: now)

                let restSeconds: Int = try Int.fetchOne(
                    db,
                    sql: "SELECT COALESCE(target_rest_seconds, 90) FROM workout_session_exercise WHERE id = ?",
                    arguments: [sessionExerciseID]
                ) ?? 90

                let started = completedAt
                let ends = started.addingTimeInterval(TimeInterval(restSeconds))
                let timerID = UUID().uuidString
                let startedAt = ISO8601Coding.string(from: started)
                let endsAt = ISO8601Coding.string(from: ends)

                try db.execute(
                    sql: """
                        INSERT INTO rest_timer_state (
                            id, workout_session_id, workout_session_exercise_id, source_set_entry_id,
                            state, started_at, paused_at, ends_at, remaining_at_pause_seconds,
                            default_duration_seconds, user_adjusted_seconds, auto_started,
                            last_action_at, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, 'running', ?, NULL, ?, NULL, ?, 0, 1, ?, ?, ?)
                        """,
                    arguments: [
                        timerID, sessionID, sessionExerciseID, setID,
                        startedAt, endsAt, restSeconds,
                        now, now, now
                    ]
                )

                try db.execute(
                    sql: """
                        INSERT INTO rest_timer_event (
                            id, rest_timer_state_id, event_type, timestamp, delta_seconds, source, note
                        ) VALUES (?, ?, 'started', ?, NULL, 'auto', NULL)
                        """,
                    arguments: [UUID().uuidString, timerID, startedAt]
                )
            }

            try Self.recomputeSessionCaches(db: db, sessionID: sessionID, now: now)
            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
    }

    public func addExercise(
        sessionID: String,
        exerciseID: String,
        defaultSetCount: Int = 3,
        defaultRestSeconds: Int = 90,
        timestamp: Date
    ) throws -> String {
        let now = ISO8601Coding.string(from: timestamp)
        let sessionExerciseID = UUID().uuidString
        try pool.write { db in
            let mode: String = try String.fetchOne(
                db,
                sql: "SELECT exercise_mode FROM exercise WHERE id = ? AND deleted_at IS NULL",
                arguments: [exerciseID]
            ) ?? ExerciseMode.weightReps.rawValue
            let exerciseMode = ExerciseMode(rawValue: mode) ?? .weightReps

            let nextOrder: Int = (try Int.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(MAX(display_order), -1) + 1
                    FROM workout_session_exercise
                    WHERE workout_session_id = ? AND deleted_at IS NULL
                    """,
                arguments: [sessionID]
            )) ?? 0

            try db.execute(
                sql: """
                    INSERT INTO workout_session_exercise (
                        id, workout_session_id, exercise_id, display_order, exercise_mode,
                        target_rest_seconds, is_collapsed, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
                    """,
                arguments: [
                    sessionExerciseID, sessionID, exerciseID, nextOrder,
                    exerciseMode.rawValue, defaultRestSeconds, now, now
                ]
            )

            let setCount = max(defaultSetCount, 1)
            for index in 0 ..< setCount {
                let setID = UUID().uuidString
                try db.execute(
                    sql: """
                        INSERT INTO set_entry (
                            id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                            created_at, updated_at
                        ) VALUES (?, ?, ?, ?, 'normal', 'planned', ?, ?)
                        """,
                    arguments: [setID, sessionExerciseID, exerciseID, index, now, now]
                )
            }

            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
        return sessionExerciseID
    }

    public func removeExercise(sessionID: String, sessionExerciseID: String, timestamp: Date) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            try Self.skipRunningRestTimers(
                db: db,
                sessionID: sessionID,
                sessionExerciseID: sessionExerciseID,
                now: now
            )

            try db.execute(
                sql: "UPDATE set_entry SET deleted_at = ? WHERE workout_session_exercise_id = ? AND deleted_at IS NULL",
                arguments: [now, sessionExerciseID]
            )
            try db.execute(
                sql: "UPDATE workout_session_exercise SET deleted_at = ? WHERE id = ? AND workout_session_id = ?",
                arguments: [now, sessionExerciseID, sessionID]
            )

            let remaining = try Row.fetchAll(
                db,
                sql: """
                    SELECT id FROM workout_session_exercise
                    WHERE workout_session_id = ? AND deleted_at IS NULL
                    ORDER BY display_order ASC, created_at ASC
                    """,
                arguments: [sessionID]
            )
            for (index, row) in remaining.enumerated() {
                let id: String = row["id"]
                try db.execute(
                    sql: "UPDATE workout_session_exercise SET display_order = ?, updated_at = ? WHERE id = ?",
                    arguments: [index, now, id]
                )
            }

            try Self.recomputeSessionCaches(db: db, sessionID: sessionID, now: now)
            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
    }

    public func skipRestTimer(sessionID: String, timestamp: Date) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            try Self.skipRunningRestTimers(db: db, sessionID: sessionID, now: now)
            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
    }

    public func completeExpiredRestTimers(sessionID: String, at now: Date) throws {
        let nowString = ISO8601Coding.string(from: now)
        try pool.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, ends_at FROM rest_timer_state
                    WHERE workout_session_id = ? AND state = 'running' AND ends_at IS NOT NULL
                    """,
                arguments: [sessionID]
            )

            for row in rows {
                let timerID: String = row["id"]
                guard let endsString: String = row["ends_at"],
                      let endsAt = try? ISO8601Coding.date(from: endsString),
                      endsAt <= now else {
                    continue
                }
                try db.execute(
                    sql: """
                        UPDATE rest_timer_state
                        SET state = 'completed', updated_at = ?, last_action_at = ?
                        WHERE id = ? AND state = 'running'
                        """,
                    arguments: [nowString, nowString, timerID]
                )
                try db.execute(
                    sql: """
                        INSERT INTO rest_timer_event (
                            id, rest_timer_state_id, event_type, timestamp, delta_seconds, source, note
                        ) VALUES (?, ?, 'completed', ?, NULL, 'auto', NULL)
                        """,
                    arguments: [UUID().uuidString, timerID, nowString]
                )
            }
        }
    }

    public func finishSession(sessionID: String, endedAt: Date) throws {
        let now = ISO8601Coding.string(from: endedAt)
        try pool.write { db in
            try Self.recomputeSessionCaches(db: db, sessionID: sessionID, now: now)
            try db.execute(
                sql: """
                    UPDATE workout_session
                    SET status = 'completed', ended_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [now, now, sessionID]
            )
            try Self.skipRunningRestTimers(db: db, sessionID: sessionID, now: now)
            try db.execute(
                sql: "DELETE FROM active_workout_state WHERE workout_session_id = ?",
                arguments: [sessionID]
            )
        }
    }

    public func discardSession(sessionID: String, endedAt: Date) throws {
        let now = ISO8601Coding.string(from: endedAt)
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE workout_session
                    SET status = 'discarded', ended_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [now, now, sessionID]
            )
            try Self.skipRunningRestTimers(db: db, sessionID: sessionID, now: now)
            try db.execute(
                sql: "DELETE FROM active_workout_state WHERE workout_session_id = ?",
                arguments: [sessionID]
            )
        }
    }

    public func sessionStatus(sessionID: String) throws -> WorkoutSessionStatus? {
        try pool.read { db in
            guard let status: String = try String.fetchOne(
                db,
                sql: "SELECT status FROM workout_session WHERE id = ? AND deleted_at IS NULL",
                arguments: [sessionID]
            ) else {
                return nil
            }
            return WorkoutSessionStatus(rawValue: status)
        }
    }
}

// MARK: - Private helpers

private extension ActiveSessionRepository {
    static func fetchExercises(db: Database, sessionID: String) throws -> [WorkoutSessionExerciseDraft] {
        let exerciseRows = try Row.fetchAll(
            db,
            sql: """
                SELECT id, exercise_id, display_order, exercise_mode
                FROM workout_session_exercise
                WHERE workout_session_id = ? AND deleted_at IS NULL
                ORDER BY display_order ASC
                """,
            arguments: [sessionID]
        )

        return try exerciseRows.map { row in
            let sessionExerciseID: String = row["id"]
            let setRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, set_index, set_type, status, weight_kg, reps, distance_km,
                           duration_seconds, rpe, rir, completed_at
                    FROM set_entry
                    WHERE workout_session_exercise_id = ? AND deleted_at IS NULL
                    ORDER BY set_index ASC
                    """,
                arguments: [sessionExerciseID]
            )

            let sets = try setRows.map { setRow -> SetEntryDraft in
                let completedAt: Date?
                if let completedString: String = setRow["completed_at"] {
                    completedAt = try ISO8601Coding.date(from: completedString)
                } else {
                    completedAt = nil
                }
                return SetEntryDraft(
                    id: setRow["id"],
                    setIndex: setRow["set_index"],
                    setType: SetType(rawValue: setRow["set_type"] as String) ?? .normal,
                    status: SetStatus(rawValue: setRow["status"] as String) ?? .planned,
                    mass: (setRow["weight_kg"] as Double?).map { Mass(kilograms: $0) },
                    reps: setRow["reps"],
                    distanceKilometers: setRow["distance_km"],
                    durationSeconds: setRow["duration_seconds"],
                    rpe: setRow["rpe"],
                    rir: setRow["rir"],
                    completedAt: completedAt
                )
            }

            return WorkoutSessionExerciseDraft(
                id: sessionExerciseID,
                exerciseID: row["exercise_id"],
                displayOrder: row["display_order"],
                exerciseMode: ExerciseMode(rawValue: row["exercise_mode"] as String) ?? .weightReps,
                sets: sets
            )
        }
    }

    static func fetchRunningRestTimer(db: Database, sessionID: String, now: Date) throws -> RestTimer? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT id, workout_session_exercise_id, source_set_entry_id, state,
                       started_at, ends_at, default_duration_seconds
                FROM rest_timer_state
                WHERE workout_session_id = ? AND state = 'running'
                ORDER BY last_action_at DESC
                LIMIT 1
                """,
            arguments: [sessionID]
        ) else {
            return nil
        }

        let startedAt: Date?
        if let startedString: String = row["started_at"] {
            startedAt = try ISO8601Coding.date(from: startedString)
        } else {
            startedAt = nil
        }

        let endsAt: Date?
        if let endsString: String = row["ends_at"] {
            endsAt = try ISO8601Coding.date(from: endsString)
        } else {
            endsAt = nil
        }

        let timer = RestTimer(
            id: row["id"],
            sessionExerciseID: row["workout_session_exercise_id"],
            sourceSetEntryID: row["source_set_entry_id"],
            phase: RestTimerPhase(rawValue: row["state"] as String) ?? .idle,
            startedAt: startedAt,
            endsAt: endsAt,
            defaultDurationSeconds: row["default_duration_seconds"] ?? 0
        )

        if timer.hasExpired(at: now) {
            return RestTimer(
                id: timer.id,
                sessionExerciseID: timer.sessionExerciseID,
                sourceSetEntryID: timer.sourceSetEntryID,
                phase: .completed,
                startedAt: timer.startedAt,
                endsAt: timer.endsAt,
                defaultDurationSeconds: timer.defaultDurationSeconds
            )
        }

        return timer
    }

    static func assertNoActiveSession(db: Database) throws {
        let count = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM workout_session
                WHERE status = 'active' AND deleted_at IS NULL
                """
        ) ?? 0
        guard count == 0 else {
            throw PersistenceError.activeSessionAlreadyExists
        }
    }

    static func insertActiveState(db: Database, sessionID: String, now: String) throws {
        try db.execute(
            sql: """
                INSERT INTO active_workout_state (
                    workout_session_id, current_workout_session_exercise_id, current_set_entry_id,
                    focused_field, paused_at, autosave_revision, recovery_state, last_opened_at, updated_at
                ) VALUES (?, NULL, NULL, NULL, NULL, 0, 'active', ?, ?)
                """,
            arguments: [sessionID, now, now]
        )
    }

    static func touchActiveState(db: Database, sessionID: String, now: String) throws {
        try db.execute(
            sql: """
                UPDATE active_workout_state
                SET last_opened_at = ?, updated_at = ?, autosave_revision = autosave_revision + 1,
                    recovery_state = 'active'
                WHERE workout_session_id = ?
                """,
            arguments: [now, now, sessionID]
        )
    }

    static func skipRunningRestTimers(
        db: Database,
        sessionID: String,
        sessionExerciseID: String? = nil,
        now: String
    ) throws {
        if let sessionExerciseID {
            try db.execute(
                sql: """
                    UPDATE rest_timer_state
                    SET state = 'skipped', updated_at = ?, last_action_at = ?
                    WHERE workout_session_id = ? AND workout_session_exercise_id = ?
                      AND state IN ('running', 'paused')
                    """,
                arguments: [now, now, sessionID, sessionExerciseID]
            )
        } else {
            try db.execute(
                sql: """
                    UPDATE rest_timer_state
                    SET state = 'skipped', updated_at = ?, last_action_at = ?
                    WHERE workout_session_id = ? AND state IN ('running', 'paused')
                    """,
                arguments: [now, now, sessionID]
            )
        }
    }

    static func recomputeSessionCaches(db: Database, sessionID: String, now: String) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT se.weight_kg, se.reps
                FROM set_entry se
                JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                WHERE wse.workout_session_id = ?
                  AND se.status = 'completed'
                  AND se.deleted_at IS NULL
                  AND wse.deleted_at IS NULL
                """,
            arguments: [sessionID]
        )

        var totalVolume = 0.0
        var totalSets = 0
        var totalReps = 0
        for row in rows {
            totalSets += 1
            if let reps: Int = row["reps"] {
                totalReps += reps
            }
            if let weight: Double = row["weight_kg"], let reps: Int = row["reps"] {
                totalVolume += weight * Double(reps)
            }
        }

        try db.execute(
            sql: """
                UPDATE workout_session
                SET total_volume_kg_cache = ?, total_set_count_cache = ?, total_rep_count_cache = ?,
                    updated_at = ?
                WHERE id = ?
                """,
            arguments: [totalVolume, totalSets, totalReps, now, sessionID]
        )
    }

    static func activeSessionID(forSetID setID: String, db: Database) throws -> String? {
        try String.fetchOne(
            db,
            sql: """
                SELECT wse.workout_session_id
                FROM set_entry se
                JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                JOIN workout_session ws ON ws.id = wse.workout_session_id
                WHERE se.id = ? AND se.deleted_at IS NULL AND ws.status = 'active'
                """,
            arguments: [setID]
        )
    }
}
