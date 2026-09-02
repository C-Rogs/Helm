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
                    SELECT ws.id, ws.title, ws.notes, ws.started_at, ws.status, ws.source,
                           aws.recovery_state
                    FROM workout_session ws
                    JOIN active_workout_state aws ON aws.workout_session_id = ws.id
                    WHERE ws.status = 'active' AND ws.deleted_at IS NULL
                    ORDER BY ws.started_at DESC
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
            let notes: String? = header["notes"]

            let exercises = try Self.fetchExercises(db: db, sessionID: sessionID)
            let restTimer = try Self.fetchRunningRestTimer(db: db, sessionID: sessionID, now: now)

            let draft = WorkoutSessionDraft(
                id: sessionID,
                title: title,
                notes: notes,
                startedAt: startedAt,
                endedAt: nil,
                status: .active,
                source: source,
                exercises: exercises
            )
            return ActiveSessionSnapshot(session: draft, recoveryState: recoveryState, restTimer: restTimer)
        }
    }

    public func startSession(title: String?, startedAt: Date, source: WorkoutSessionSource = .manual) throws -> String {
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
                    ) VALUES (?, ?, ?, NULL, 'active', ?, 0, 0, 0, ?, ?)
                    """,
                arguments: [sessionID, title, nowString, source.rawValue, nowString, nowString]
            )
            try Self.insertActiveState(db: db, sessionID: sessionID, now: nowString)
        }
        return sessionID
    }

    public func startSessionFromTemplate(
        template: WorkoutTemplateDraft,
        startedAt: Date
    ) throws -> String {
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
                    ) VALUES (?, ?, ?, NULL, 'active', 'template', 0, 0, 0, ?, ?)
                    """,
                arguments: [sessionID, template.name, nowString, nowString, nowString]
            )
            try Self.insertActiveState(db: db, sessionID: sessionID, now: nowString)

            for exercise in template.exercises.sorted(by: { $0.displayOrder < $1.displayOrder }) {
                let sessionExerciseID = UUID().uuidString
                let mode: String = try String.fetchOne(
                    db,
                    sql: "SELECT exercise_mode FROM exercise WHERE id = ? AND deleted_at IS NULL",
                    arguments: [exercise.exerciseID]
                ) ?? ExerciseMode.weightReps.rawValue
                let exerciseMode = ExerciseMode(rawValue: mode) ?? .weightReps
                let restSeconds = exercise.defaultRestSeconds ?? 90
                let setCount = max(exercise.targetSetCount ?? 3, 1)

                try db.execute(
                    sql: """
                        INSERT INTO workout_session_exercise (
                            id, workout_session_id, exercise_id, display_order, exercise_mode,
                            target_rest_seconds, is_collapsed, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
                        """,
                    arguments: [
                        sessionExerciseID, sessionID, exercise.exerciseID, exercise.displayOrder,
                        exerciseMode.rawValue, restSeconds, nowString, nowString
                    ]
                )

                for index in 0 ..< setCount {
                    let setID = UUID().uuidString
                    try db.execute(
                        sql: """
                            INSERT INTO set_entry (
                                id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                                weight_kg, reps, created_at, updated_at
                            ) VALUES (?, ?, ?, ?, 'normal', 'planned', ?, ?, ?, ?)
                            """,
                        arguments: [
                            setID,
                            sessionExerciseID,
                            exercise.exerciseID,
                            index,
                            exercise.targetMass?.kilograms,
                            exercise.targetRepMin,
                            nowString,
                            nowString
                        ]
                    )
                }
            }
        }
        return sessionID
    }

    public func startSessionFromPrescription(
        _ prescription: SessionPrescription,
        startedAt: Date
    ) throws -> String {
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
                    ) VALUES (?, ?, ?, NULL, 'active', 'prescription', 0, 0, 0, ?, ?)
                    """,
                arguments: [sessionID, prescription.title ?? "Today's session", nowString, nowString, nowString]
            )
            try Self.insertActiveState(db: db, sessionID: sessionID, now: nowString)

            for exercise in prescription.exercises.sorted(by: { $0.order < $1.order }) {
                let sessionExerciseID = UUID().uuidString
                let mode: String = try String.fetchOne(
                    db,
                    sql: "SELECT exercise_mode FROM exercise WHERE id = ? AND deleted_at IS NULL",
                    arguments: [exercise.exerciseID]
                ) ?? ExerciseMode.weightReps.rawValue
                let exerciseMode = ExerciseMode(rawValue: mode) ?? .weightReps
                let restSeconds = 90
                let warmupCount = max(exercise.warmupSets, 0)
                let workingCount = max(exercise.targetSets, 1)
                let targetReps = exercise.targetRepMin ?? exercise.targetRepMax

                try db.execute(
                    sql: """
                        INSERT INTO workout_session_exercise (
                            id, workout_session_id, exercise_id, display_order, exercise_mode,
                            target_rest_seconds, is_collapsed, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
                        """,
                    arguments: [
                        sessionExerciseID, sessionID, exercise.exerciseID, exercise.order,
                        exerciseMode.rawValue, restSeconds, nowString, nowString
                    ]
                )

                var setIndex = 0
                for _ in 0 ..< warmupCount {
                    let setID = UUID().uuidString
                    try db.execute(
                        sql: """
                            INSERT INTO set_entry (
                                id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                                weight_kg, reps, rpe, created_at, updated_at
                            ) VALUES (?, ?, ?, ?, 'warmup', 'planned', ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            setID,
                            sessionExerciseID,
                            exercise.exerciseID,
                            setIndex,
                            exercise.targetMass?.kilograms,
                            targetReps,
                            exercise.targetRPE,
                            nowString,
                            nowString
                        ]
                    )
                    setIndex += 1
                }
                for _ in 0 ..< workingCount {
                    let setID = UUID().uuidString
                    try db.execute(
                        sql: """
                            INSERT INTO set_entry (
                                id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                                weight_kg, reps, rpe, created_at, updated_at
                            ) VALUES (?, ?, ?, ?, 'normal', 'planned', ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            setID,
                            sessionExerciseID,
                            exercise.exerciseID,
                            setIndex,
                            exercise.targetMass?.kilograms,
                            targetReps,
                            exercise.targetRPE,
                            nowString,
                            nowString
                        ]
                    )
                    setIndex += 1
                }
            }
        }
        return sessionID
    }

    public func startSessionFromImport(
        _ plan: ImportedWorkoutPlan,
        startedAt: Date
    ) throws -> String {
        let sessionID = UUID().uuidString
        let nowString = ISO8601Coding.string(from: startedAt)
        try pool.write { db in
            try Self.assertNoActiveSession(db: db)
            try db.execute(
                sql: """
                    INSERT INTO workout_session (
                        id, title, notes, started_at, ended_at, status, source,
                        total_volume_kg_cache, total_set_count_cache, total_rep_count_cache,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, NULL, 'active', 'import', 0, 0, 0, ?, ?)
                    """,
                arguments: [sessionID, plan.title, plan.contextNotes, nowString, nowString, nowString]
            )
            try Self.insertActiveState(db: db, sessionID: sessionID, now: nowString)

            for exercise in plan.exercises.sorted(by: { $0.displayOrder < $1.displayOrder }) {
                let sessionExerciseID = UUID().uuidString
                let restSeconds = exercise.restDurationSeconds ?? 90

                try db.execute(
                    sql: """
                        INSERT INTO workout_session_exercise (
                            id, workout_session_id, exercise_id, display_order, exercise_mode,
                            target_rest_seconds, is_collapsed, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
                        """,
                    arguments: [
                        sessionExerciseID,
                        sessionID,
                        exercise.exerciseID,
                        exercise.displayOrder,
                        exercise.exerciseMode.rawValue,
                        restSeconds,
                        nowString,
                        nowString
                    ]
                )

                for set in exercise.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
                    let setID = UUID().uuidString
                    try db.execute(
                        sql: """
                            INSERT INTO set_entry (
                                id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                                weight_kg, reps, rpe, created_at, updated_at
                            ) VALUES (?, ?, ?, ?, ?, 'planned', ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            setID,
                            sessionExerciseID,
                            exercise.exerciseID,
                            set.setIndex,
                            set.setType.rawValue,
                            set.mass?.kilograms,
                            set.reps,
                            set.rpe,
                            nowString,
                            nowString
                        ]
                    )
                }
            }
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

    public func updateSetType(setID: String, setType: SetType, timestamp: Date) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            guard try Self.activeSessionID(forSetID: setID, db: db) != nil else {
                throw PersistenceError.recordNotFound("set \(setID)")
            }
            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET set_type = ?, updated_at = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [setType.rawValue, now, setID]
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
                sql: """
                    SELECT se.status AS status
                    FROM set_entry se
                    INNER JOIN workout_session_exercise wse
                        ON wse.id = se.workout_session_exercise_id
                    WHERE se.id = ?
                      AND se.workout_session_exercise_id = ?
                      AND wse.workout_session_id = ?
                      AND se.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                    """,
                arguments: [setID, sessionExerciseID, sessionID]
            )
            guard let before else {
                throw PersistenceError.recordNotFound("set \(setID) in session \(sessionID)")
            }
            let wasCompleted = (before["status"] as String?) == SetStatus.completed.rawValue

            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET logged_exercise_id = COALESCE(
                            logged_exercise_id,
                            (SELECT exercise_id FROM workout_session_exercise WHERE id = ?)
                        ),
                        bodyweight_kg_snapshot = CASE
                            WHEN bodyweight_kg_snapshot IS NULL
                                 AND (SELECT exercise_mode FROM workout_session_exercise WHERE id = ?) = ?
                            THEN ?
                            ELSE bodyweight_kg_snapshot
                        END,
                        status = 'completed', completed_at = ?, updated_at = ?
                    WHERE id = ? AND workout_session_exercise_id = ? AND deleted_at IS NULL
                    """,
                arguments: [
                    sessionExerciseID,
                    sessionExerciseID,
                    ExerciseMode.bodyweightReps.rawValue,
                    try Self.latestBodyweightKg(db: db),
                    now,
                    now,
                    setID,
                    sessionExerciseID
                ]
            )

            guard db.changesCount == 1 || wasCompleted else {
                throw PersistenceError.recordNotFound("set \(setID) update")
            }

            if !wasCompleted {
                try Self.skipRunningRestTimers(db: db, sessionID: sessionID, now: now)

                let restSecondsRaw: Int = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COALESCE(target_rest_seconds, 90)
                        FROM workout_session_exercise
                        WHERE id = ? AND workout_session_id = ? AND deleted_at IS NULL
                        """,
                    arguments: [sessionExerciseID, sessionID]
                ) ?? 90
                let restSeconds = max(1, restSecondsRaw)

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

    public func uncompleteSet(
        sessionID: String,
        sessionExerciseID: String,
        setID: String,
        timestamp: Date
    ) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            let before = try Row.fetchOne(
                db,
                sql: """
                    SELECT se.status AS status
                    FROM set_entry se
                    INNER JOIN workout_session_exercise wse
                        ON wse.id = se.workout_session_exercise_id
                    WHERE se.id = ?
                      AND se.workout_session_exercise_id = ?
                      AND wse.workout_session_id = ?
                      AND se.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                    """,
                arguments: [setID, sessionExerciseID, sessionID]
            )
            guard (before?["status"] as String?) == SetStatus.completed.rawValue else { return }

            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET status = 'planned', completed_at = NULL, updated_at = ?
                    WHERE id = ? AND workout_session_exercise_id = ? AND deleted_at IS NULL
                    """,
                arguments: [now, setID, sessionExerciseID]
            )

            try db.execute(
                sql: """
                    UPDATE rest_timer_state
                    SET state = 'skipped', updated_at = ?, last_action_at = ?
                    WHERE workout_session_id = ? AND source_set_entry_id = ?
                      AND state IN ('running', 'paused')
                    """,
                arguments: [now, now, sessionID, setID]
            )

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
            let preset = try Self.previousPerformancePreset(
                db: db,
                exerciseID: exerciseID,
                excludingSessionID: sessionID
            )
            for index in 0 ..< setCount {
                let setID = UUID().uuidString
                try db.execute(
                    sql: """
                        INSERT INTO set_entry (
                            id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                            weight_kg, reps, rpe, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, 'normal', 'planned', ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        setID,
                        sessionExerciseID,
                        exerciseID,
                        index,
                        preset?.mass?.kilograms,
                        preset?.reps,
                        preset?.rpe,
                        now,
                        now
                    ]
                )
            }

            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
        return sessionExerciseID
    }

    public func removeExercise(sessionID: String, sessionExerciseID: String, timestamp: Date) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            let owned = try Row.fetchOne(
                db,
                sql: """
                    SELECT id FROM workout_session_exercise
                    WHERE id = ? AND workout_session_id = ? AND deleted_at IS NULL
                    """,
                arguments: [sessionExerciseID, sessionID]
            )
            guard owned != nil else {
                throw PersistenceError.recordNotFound("session exercise \(sessionExerciseID)")
            }

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

    public func updateSessionNotes(sessionID: String, notes: String?, timestamp: Date) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE workout_session
                    SET notes = ?, updated_at = ?
                    WHERE id = ? AND status = 'active' AND deleted_at IS NULL
                    """,
                arguments: [notes, now, sessionID]
            )
            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
    }

    public func reorderExercises(
        sessionID: String,
        orderedSessionExerciseIDs: [String],
        timestamp: Date
    ) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            let existingIDs = try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM workout_session_exercise
                    WHERE workout_session_id = ? AND deleted_at IS NULL
                    ORDER BY display_order ASC
                    """,
                arguments: [sessionID]
            )
            let existingSet = Set(existingIDs)
            let orderedSet = Set(orderedSessionExerciseIDs)
            guard existingSet == orderedSet,
                  orderedSessionExerciseIDs.count == existingIDs.count else {
                throw PersistenceError.invalidReorder
            }

            for (index, sessionExerciseID) in orderedSessionExerciseIDs.enumerated() {
                try db.execute(
                    sql: """
                        UPDATE workout_session_exercise
                        SET display_order = ?, updated_at = ?
                        WHERE id = ? AND workout_session_id = ?
                        """,
                    arguments: [index, now, sessionExerciseID, sessionID]
                )
            }

            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
    }

    public func adjustRestTimer(sessionID: String, deltaSeconds: Int, timestamp: Date) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, ends_at, user_adjusted_seconds
                    FROM rest_timer_state
                    WHERE workout_session_id = ? AND state = 'running'
                    ORDER BY last_action_at DESC
                    LIMIT 1
                    """,
                arguments: [sessionID]
            ) else {
                throw PersistenceError.recordNotFound("running rest timer")
            }

            let timerID: String = row["id"]
            guard let endsString: String = row["ends_at"],
                  let endsAt = try? ISO8601Coding.date(from: endsString) else {
                throw PersistenceError.recordNotFound("running rest timer ends_at")
            }

            let remaining = max(0, endsAt.timeIntervalSince(timestamp))
            let adjustedRemaining = max(0, remaining + TimeInterval(deltaSeconds))
            let newEndsAt = timestamp.addingTimeInterval(adjustedRemaining)
            let appliedDelta = Int(adjustedRemaining - remaining)
            let newEndsString = ISO8601Coding.string(from: newEndsAt)
            let userAdjusted: Int = row["user_adjusted_seconds"] ?? 0

            guard appliedDelta != 0 else { return }

            try db.execute(
                sql: """
                    UPDATE rest_timer_state
                    SET ends_at = ?, user_adjusted_seconds = ?, updated_at = ?, last_action_at = ?
                    WHERE id = ? AND state = 'running'
                    """,
                arguments: [newEndsString, userAdjusted + appliedDelta, now, now, timerID]
            )

            try db.execute(
                sql: """
                    INSERT INTO rest_timer_event (
                        id, rest_timer_state_id, event_type, timestamp, delta_seconds, source, note
                    ) VALUES (?, ?, 'adjusted', ?, ?, 'user', NULL)
                    """,
                arguments: [UUID().uuidString, timerID, now, appliedDelta]
            )

            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
    }

    public func updateExerciseRest(
        sessionID: String,
        sessionExerciseID: String,
        seconds: Int,
        timestamp: Date
    ) throws {
        let now = ISO8601Coding.string(from: timestamp)
        let clampedSeconds = max(1, seconds)
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE workout_session_exercise
                    SET target_rest_seconds = ?, updated_at = ?
                    WHERE id = ? AND workout_session_id = ? AND deleted_at IS NULL
                    """,
                arguments: [clampedSeconds, now, sessionExerciseID, sessionID]
            )
            guard db.changesCount == 1 else {
                throw PersistenceError.recordNotFound("session exercise \(sessionExerciseID)")
            }
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

    public func startManualRestTimer(
        sessionID: String,
        sessionExerciseID: String?,
        durationSeconds: Int,
        startedAt: Date
    ) throws {
        let clampedDuration = max(1, durationSeconds)
        let now = ISO8601Coding.string(from: startedAt)
        let ends = startedAt.addingTimeInterval(TimeInterval(clampedDuration))
        let endsAt = ISO8601Coding.string(from: ends)

        try pool.write { db in
            try Self.skipRunningRestTimers(db: db, sessionID: sessionID, now: now)

            let timerID = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO rest_timer_state (
                        id, workout_session_id, workout_session_exercise_id, source_set_entry_id,
                        state, started_at, paused_at, ends_at, remaining_at_pause_seconds,
                        default_duration_seconds, user_adjusted_seconds, auto_started,
                        last_action_at, created_at, updated_at
                    ) VALUES (?, ?, ?, NULL, 'running', ?, NULL, ?, NULL, ?, 0, 0, ?, ?, ?)
                    """,
                arguments: [
                    timerID, sessionID, sessionExerciseID,
                    now, endsAt, clampedDuration,
                    now, now, now
                ]
            )

            try db.execute(
                sql: """
                    INSERT INTO rest_timer_event (
                        id, rest_timer_state_id, event_type, timestamp, delta_seconds, source, note
                    ) VALUES (?, ?, 'started', ?, NULL, 'manual', NULL)
                    """,
                arguments: [UUID().uuidString, timerID, now]
            )

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

    public func syncFromPrescription(
        sessionID: String,
        prescription: SessionPrescription,
        timestamp: Date
    ) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            let existing = try Self.fetchExercises(db: db, sessionID: sessionID)
            let existingSorted = existing.sorted { $0.displayOrder < $1.displayOrder }
            let sorted = prescription.exercises.sorted { $0.order < $1.order }

            for (index, prescribed) in sorted.enumerated() {
                if let matched = existing.first(where: { $0.exerciseID == prescribed.exerciseID }) {
                    let sessionExerciseID = matched.id

                    try db.execute(
                        sql: """
                            UPDATE workout_session_exercise
                            SET display_order = ?, updated_at = ?
                            WHERE id = ? AND workout_session_id = ?
                            """,
                        arguments: [index, now, sessionExerciseID, sessionID]
                    )

                    try Self.adjustSetComposition(
                        db: db,
                        sessionExerciseID: sessionExerciseID,
                        exerciseID: prescribed.exerciseID,
                        targetWorkingSets: max(prescribed.targetSets, 1),
                        targetWarmupSets: max(prescribed.warmupSets, 0),
                        existingSets: matched.sets,
                        now: now,
                        templateMassKg: prescribed.targetMass?.kilograms,
                        templateReps: prescribed.targetRepMin ?? prescribed.targetRepMax,
                        templateRPE: prescribed.targetRPE
                    )
                    try Self.syncPlannedWorkingTargets(
                        db: db,
                        sessionExerciseID: sessionExerciseID,
                        previousSets: matched.sets,
                        prescribedMassKg: prescribed.targetMass?.kilograms,
                        prescribedReps: prescribed.targetRepMin ?? prescribed.targetRepMax,
                        now: now
                    )
                } else if index < existingSorted.count {
                    let sessionExercise = existingSorted[index]
                    let sessionExerciseID = sessionExercise.id

                    if sessionExercise.exerciseID != prescribed.exerciseID {
                        try db.execute(
                            sql: """
                                UPDATE workout_session_exercise
                                SET exercise_id = ?, updated_at = ?
                                WHERE id = ? AND workout_session_id = ?
                                """,
                            arguments: [prescribed.exerciseID, now, sessionExerciseID, sessionID]
                        )
                        try db.execute(
                            sql: """
                                UPDATE set_entry
                                SET logged_exercise_id = ?
                                WHERE workout_session_exercise_id = ?
                                  AND status != 'completed'
                                  AND deleted_at IS NULL
                                """,
                            arguments: [prescribed.exerciseID, sessionExerciseID]
                        )
                    }

                    try db.execute(
                        sql: """
                            UPDATE workout_session_exercise
                            SET display_order = ?, updated_at = ?
                            WHERE id = ? AND workout_session_id = ?
                            """,
                        arguments: [index, now, sessionExerciseID, sessionID]
                    )

                    try Self.adjustSetComposition(
                        db: db,
                        sessionExerciseID: sessionExerciseID,
                        exerciseID: prescribed.exerciseID,
                        targetWorkingSets: max(prescribed.targetSets, 1),
                        targetWarmupSets: max(prescribed.warmupSets, 0),
                        existingSets: sessionExercise.sets,
                        now: now,
                        templateMassKg: prescribed.targetMass?.kilograms,
                        templateReps: prescribed.targetRepMin ?? prescribed.targetRepMax,
                        templateRPE: prescribed.targetRPE
                    )
                    try Self.syncPlannedWorkingTargets(
                        db: db,
                        sessionExerciseID: sessionExerciseID,
                        previousSets: sessionExercise.sets,
                        prescribedMassKg: prescribed.targetMass?.kilograms,
                        prescribedReps: prescribed.targetRepMin ?? prescribed.targetRepMax,
                        now: now
                    )
                } else {
                    try Self.insertPrescribedExercise(
                        db: db,
                        sessionID: sessionID,
                        prescribed: prescribed,
                        displayOrder: index,
                        now: now
                    )
                }
            }

            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
    }

    public func restoreExerciseLayout(
        sessionID: String,
        exercises: [WorkoutSessionExerciseDraft],
        timestamp: Date
    ) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            let existing = try Self.fetchExercises(db: db, sessionID: sessionID)
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            let sorted = exercises.sorted { $0.displayOrder < $1.displayOrder }

            for saved in sorted {
                guard let current = existingByID[saved.id] else { continue }
                let sessionExerciseID = saved.id

                if current.exerciseID != saved.exerciseID {
                    try db.execute(
                        sql: """
                            UPDATE workout_session_exercise
                            SET exercise_id = ?, updated_at = ?
                            WHERE id = ? AND workout_session_id = ?
                            """,
                        arguments: [saved.exerciseID, now, sessionExerciseID, sessionID]
                    )
                    try db.execute(
                        sql: """
                            UPDATE set_entry
                            SET logged_exercise_id = ?
                            WHERE workout_session_exercise_id = ?
                              AND status != 'completed'
                              AND deleted_at IS NULL
                            """,
                        arguments: [saved.exerciseID, sessionExerciseID]
                    )
                }

                try db.execute(
                    sql: """
                        UPDATE workout_session_exercise
                        SET display_order = ?, updated_at = ?
                        WHERE id = ? AND workout_session_id = ?
                        """,
                    arguments: [saved.displayOrder, now, sessionExerciseID, sessionID]
                )

                try Self.adjustSetComposition(
                    db: db,
                    sessionExerciseID: sessionExerciseID,
                    exerciseID: saved.exerciseID,
                    targetWorkingSets: max(saved.sets.filter { $0.setType.countsAsPrescribedWorkingSet }.count, 1),
                    targetWarmupSets: saved.sets.filter { $0.setType.isWarmup }.count,
                    existingSets: current.sets,
                    now: now
                )
            }

            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
    }
}

// MARK: - Shared fetch helpers

extension ActiveSessionRepository {
    static func fetchExercises(db: Database, sessionID: String) throws -> [WorkoutSessionExerciseDraft] {
        let exerciseRows = try Row.fetchAll(
            db,
            sql: """
                SELECT id, exercise_id, display_order, exercise_mode, target_rest_seconds
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
                targetRestSeconds: row["target_rest_seconds"],
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

    static func latestBodyweightKg(db: Database) throws -> Double? {
        try Double.fetchOne(
            db,
            sql: """
                SELECT mass_kg
                FROM body_composition
                WHERE mass_kg IS NOT NULL
                ORDER BY measured_at DESC
                LIMIT 1
                """
        )
    }

    struct PerformancePreset: Sendable {
        let mass: Mass?
        let reps: Int?
        let rpe: Double?
    }

    static func previousPerformancePreset(
        db: Database,
        exerciseID: String,
        excludingSessionID: String
    ) throws -> PerformancePreset? {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT se.weight_kg, se.reps, se.rpe
                FROM set_entry se
                JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                JOIN workout_session ws ON ws.id = wse.workout_session_id
                WHERE se.logged_exercise_id = ?
                  AND se.status = 'completed'
                  AND se.deleted_at IS NULL
                  AND wse.deleted_at IS NULL
                  AND ws.deleted_at IS NULL
                  AND ws.status = 'completed'
                  AND ws.id != ?
                ORDER BY se.completed_at DESC
                LIMIT 1
                """,
            arguments: [exerciseID, excludingSessionID]
        ) else {
            return nil
        }

        return PerformancePreset(
            mass: (row["weight_kg"] as Double?).map { Mass(kilograms: $0) },
            reps: row["reps"],
            rpe: row["rpe"]
        )
    }

    static func insertPrescribedExercise(
        db: Database,
        sessionID: String,
        prescribed: PrescribedExercise,
        displayOrder: Int,
        now: String
    ) throws {
        let sessionExerciseID = UUID().uuidString
        let mode: String = try String.fetchOne(
            db,
            sql: "SELECT exercise_mode FROM exercise WHERE id = ? AND deleted_at IS NULL",
            arguments: [prescribed.exerciseID]
        ) ?? ExerciseMode.weightReps.rawValue
        let exerciseMode = ExerciseMode(rawValue: mode) ?? .weightReps

        try db.execute(
            sql: """
                INSERT INTO workout_session_exercise (
                    id, workout_session_id, exercise_id, display_order, exercise_mode,
                    target_rest_seconds, is_collapsed, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, 90, 0, ?, ?)
                """,
            arguments: [
                sessionExerciseID,
                sessionID,
                prescribed.exerciseID,
                displayOrder,
                exerciseMode.rawValue,
                now,
                now
            ]
        )

        let warmupCount = max(prescribed.warmupSets, 0)
        let workingCount = max(prescribed.targetSets, 1)
        let targetReps = prescribed.targetRepMin ?? prescribed.targetRepMax
        let preset = try previousPerformancePreset(
            db: db,
            exerciseID: prescribed.exerciseID,
            excludingSessionID: sessionID
        )

        var setIndex = 0
        for _ in 0 ..< warmupCount {
            let setID = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                        weight_kg, reps, rpe, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, 'warmup', 'planned', ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    setID,
                    sessionExerciseID,
                    prescribed.exerciseID,
                    setIndex,
                    prescribed.targetMass?.kilograms ?? preset?.mass?.kilograms,
                    targetReps ?? preset?.reps,
                    prescribed.targetRPE ?? preset?.rpe,
                    now,
                    now
                ]
            )
            setIndex += 1
        }
        for _ in 0 ..< workingCount {
            let setID = UUID().uuidString
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                        weight_kg, reps, rpe, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, 'normal', 'planned', ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    setID,
                    sessionExerciseID,
                    prescribed.exerciseID,
                    setIndex,
                    prescribed.targetMass?.kilograms ?? preset?.mass?.kilograms,
                    targetReps ?? preset?.reps,
                    prescribed.targetRPE ?? preset?.rpe,
                    now,
                    now
                ]
            )
            setIndex += 1
        }
    }

    static func recomputeSessionCaches(db: Database, sessionID: String, now: String) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT se.weight_kg, se.reps, se.bodyweight_kg_snapshot, wse.exercise_mode
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
            let reps: Int = row["reps"] ?? 0
            totalReps += reps
            let weight: Double? = row["weight_kg"]
            let bodyweight: Double? = row["bodyweight_kg_snapshot"]
            let modeRaw: String = row["exercise_mode"] ?? ExerciseMode.weightReps.rawValue
            let mode = ExerciseMode(rawValue: modeRaw) ?? .weightReps
            totalVolume += BodyweightVolume.setVolumeKg(
                loggedMassKg: weight,
                reps: reps,
                exerciseMode: mode,
                bodyweightKg: bodyweight
            )
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

    public func adjustExerciseSetCount(
        sessionID: String,
        sessionExerciseID: String,
        targetSetCount: Int,
        timestamp: Date
    ) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            guard let sessionExercise = try Self.fetchExercises(db: db, sessionID: sessionID)
                .first(where: { $0.id == sessionExerciseID })
            else {
                throw PersistenceError.recordNotFound("session exercise")
            }
            try Self.adjustSetComposition(
                db: db,
                sessionExerciseID: sessionExerciseID,
                exerciseID: sessionExercise.exerciseID,
                targetWorkingSets: max(targetSetCount, 1),
                targetWarmupSets: sessionExercise.sets.filter { $0.setType.isWarmup }.count,
                existingSets: sessionExercise.sets,
                now: now
            )
            try Self.touchActiveState(db: db, sessionID: sessionID, now: now)
        }
    }

    /// Coach load/rep fills update `PrescribedExercise` targets, but composition
    /// only uses those values when inserting new rows. Write them onto remaining
    /// planned working sets when they actually changed.
    private static func syncPlannedWorkingTargets(
        db: Database,
        sessionExerciseID: String,
        previousSets: [SetEntryDraft],
        prescribedMassKg: Double?,
        prescribedReps: Int?,
        now: String
    ) throws {
        let previousPlannedWorking = previousSets.filter {
            $0.setType.countsAsPrescribedWorkingSet && $0.status == .planned
        }
        let shouldWriteMass: Bool = {
            guard let prescribedMassKg else { return false }
            if let currentKg = previousPlannedWorking.first?.mass?.kilograms,
               abs(currentKg - prescribedMassKg) < 0.001 {
                return false
            }
            return true
        }()
        let shouldWriteReps: Bool = {
            guard let prescribedReps else { return false }
            return previousPlannedWorking.first?.reps != prescribedReps
        }()
        guard shouldWriteMass || shouldWriteReps else { return }

        let types = SetType.allCases.filter(\.countsAsPrescribedWorkingSet).map(\.rawValue)
        guard !types.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: types.count).joined(separator: ", ")
        let assignments: [String]
        var arguments: [DatabaseValueConvertible] = []
        if shouldWriteMass, let prescribedMassKg {
            assignments = shouldWriteReps ? ["weight_kg = ?", "reps = ?", "updated_at = ?"] : ["weight_kg = ?", "updated_at = ?"]
            arguments.append(prescribedMassKg)
            if shouldWriteReps, let prescribedReps {
                arguments.append(prescribedReps)
            }
        } else {
            assignments = ["reps = ?", "updated_at = ?"]
            if let prescribedReps {
                arguments.append(prescribedReps)
            }
        }
        arguments.append(now)
        arguments.append(sessionExerciseID)
        arguments.append(SetStatus.planned.rawValue)
        arguments.append(contentsOf: types)
        try db.execute(
            sql: """
                UPDATE set_entry
                SET \(assignments.joined(separator: ", "))
                WHERE workout_session_exercise_id = ?
                  AND deleted_at IS NULL
                  AND status = ?
                  AND set_type IN (\(placeholders))
                """,
            arguments: StatementArguments(arguments)
        )
    }

    static func adjustSetComposition(
        db: Database,
        sessionExerciseID: String,
        exerciseID: String,
        targetWorkingSets: Int,
        targetWarmupSets: Int,
        existingSets: [SetEntryDraft],
        now: String,
        templateMassKg: Double? = nil,
        templateReps: Int? = nil,
        templateRPE: Double? = nil
    ) throws {
        let warmups = existingSets.filter { $0.setType.isWarmup }
        let prescribedWorking = existingSets.filter { $0.setType.countsAsPrescribedWorkingSet }
        let completedWarmups = warmups.filter { $0.status == .completed }.count
        let completedWorking = prescribedWorking.filter { $0.status == .completed }.count
        let desiredWarmups = max(targetWarmupSets, completedWarmups)
        let desiredWorking = max(max(targetWorkingSets, 1), completedWorking)

        try adjustTypedSetCount(
            db: db,
            sessionExerciseID: sessionExerciseID,
            exerciseID: exerciseID,
            setType: .warmup,
            desiredCount: desiredWarmups,
            existingOfType: warmups,
            now: now,
            templateMassKg: templateMassKg,
            templateReps: templateReps,
            templateRPE: templateRPE
        )
        // Only add/remove normal working slots. Drop sets and other intensity rows stay put.
        try adjustPrescribedWorkingSetCount(
            db: db,
            sessionExerciseID: sessionExerciseID,
            exerciseID: exerciseID,
            desiredCount: desiredWorking,
            existingWorking: prescribedWorking,
            now: now,
            templateMassKg: templateMassKg,
            templateReps: templateReps,
            templateRPE: templateRPE
        )
        try normalizeSetIndices(db: db, sessionExerciseID: sessionExerciseID, now: now)
    }

    /// Legacy entry point: changes working-set count while preserving warm-ups and drops.
    static func adjustSetCount(
        db: Database,
        sessionExerciseID: String,
        exerciseID: String,
        targetSetCount: Int,
        existingSets: [SetEntryDraft],
        now: String
    ) throws {
        try adjustSetComposition(
            db: db,
            sessionExerciseID: sessionExerciseID,
            exerciseID: exerciseID,
            targetWorkingSets: max(targetSetCount, 1),
            targetWarmupSets: existingSets.filter { $0.setType.isWarmup }.count,
            existingSets: existingSets,
            now: now
        )
    }

    private static func adjustPrescribedWorkingSetCount(
        db: Database,
        sessionExerciseID: String,
        exerciseID: String,
        desiredCount: Int,
        existingWorking: [SetEntryDraft],
        now: String,
        templateMassKg: Double?,
        templateReps: Int?,
        templateRPE: Double?
    ) throws {
        if existingWorking.count < desiredCount {
            try adjustTypedSetCount(
                db: db,
                sessionExerciseID: sessionExerciseID,
                exerciseID: exerciseID,
                setType: .normal,
                desiredCount: desiredCount,
                existingOfType: existingWorking,
                now: now,
                templateMassKg: templateMassKg,
                templateReps: templateReps,
                templateRPE: templateRPE
            )
            return
        }

        if existingWorking.count > desiredCount {
            // Prefer removing planned normals; never touch completed or drop rows (drops excluded).
            let removable = existingWorking
                .filter { $0.status != .completed }
                .sorted { lhs, rhs in
                    if lhs.setType == .normal && rhs.setType != .normal { return true }
                    if lhs.setType != .normal && rhs.setType == .normal { return false }
                    return lhs.setIndex > rhs.setIndex
                }
            var toRemove = existingWorking.count - desiredCount
            for set in removable where toRemove > 0 {
                try db.execute(
                    sql: "DELETE FROM set_entry WHERE id = ? AND deleted_at IS NULL",
                    arguments: [set.id]
                )
                toRemove -= 1
            }
        }
    }

    private static func adjustTypedSetCount(
        db: Database,
        sessionExerciseID: String,
        exerciseID: String,
        setType: SetType,
        desiredCount: Int,
        existingOfType: [SetEntryDraft],
        now: String,
        templateMassKg: Double?,
        templateReps: Int?,
        templateRPE: Double?
    ) throws {
        if existingOfType.count < desiredCount {
            let toAdd = desiredCount - existingOfType.count
            let maxIndex = try Int.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(MAX(set_index), -1)
                    FROM set_entry
                    WHERE workout_session_exercise_id = ? AND deleted_at IS NULL
                    """,
                arguments: [sessionExerciseID]
            ) ?? -1
            let startIndex = maxIndex + 1
            for offset in 0 ..< toAdd {
                let setID = UUID().uuidString
                try db.execute(
                    sql: """
                        INSERT INTO set_entry (
                            id, workout_session_exercise_id, logged_exercise_id, set_index, set_type, status,
                            weight_kg, reps, rpe, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, 'planned', ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        setID,
                        sessionExerciseID,
                        exerciseID,
                        startIndex + offset,
                        setType.rawValue,
                        templateMassKg,
                        templateReps,
                        templateRPE,
                        now,
                        now
                    ]
                )
            }
        } else if existingOfType.count > desiredCount {
            let removable = existingOfType
                .filter { $0.status != .completed }
                .sorted { $0.setIndex > $1.setIndex }
            var toRemove = existingOfType.count - desiredCount
            for set in removable where toRemove > 0 {
                try db.execute(
                    sql: "DELETE FROM set_entry WHERE id = ? AND deleted_at IS NULL",
                    arguments: [set.id]
                )
                toRemove -= 1
            }
        }
    }

    private static func normalizeSetIndices(
        db: Database,
        sessionExerciseID: String,
        now: String
    ) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT id, set_type, set_index, status
                FROM set_entry
                WHERE workout_session_exercise_id = ? AND deleted_at IS NULL
                ORDER BY set_index ASC
                """,
            arguments: [sessionExerciseID]
        )
        let warmups = rows.filter { ($0["set_type"] as String) == SetType.warmup.rawValue }
            .sorted { ($0["set_index"] as Int) < ($1["set_index"] as Int) }
        let prescribedWorking = rows.filter {
            (SetType(rawValue: $0["set_type"] as String) ?? .normal).countsAsPrescribedWorkingSet
        }
        .sorted { ($0["set_index"] as Int) < ($1["set_index"] as Int) }
        let intensity = rows.filter {
            (SetType(rawValue: $0["set_type"] as String) ?? .normal).isPreservedIntensityTechnique
        }
        .sorted { ($0["set_index"] as Int) < ($1["set_index"] as Int) }
        let accountedIDs = Set(
            (warmups + prescribedWorking + intensity).map { $0["id"] as String }
        )
        let other = rows.filter { !accountedIDs.contains($0["id"] as String) }
            .sorted { ($0["set_index"] as Int) < ($1["set_index"] as Int) }
        let ordered = warmups + prescribedWorking + intensity + other
        // Two-phase rewrite avoids UNIQUE(workout_session_exercise_id, set_index) collisions.
        let stagingBase = 10_000
        for (index, row) in ordered.enumerated() {
            let id: String = row["id"]
            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET set_index = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [stagingBase + index, now, id]
            )
        }
        for (index, row) in ordered.enumerated() {
            let id: String = row["id"]
            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET set_index = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [index, now, id]
            )
        }
    }
}
