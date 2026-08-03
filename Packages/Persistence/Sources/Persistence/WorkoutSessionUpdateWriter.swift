import Core
import Foundation
import GRDB

enum WorkoutSessionUpdateWriter {
    static func apply(_ draft: WorkoutSessionDraft, now: String, in db: Database) throws {
        try db.execute(
            sql: """
                UPDATE workout_session
                SET title = ?, updated_at = ?
                WHERE id = ?
                """,
            arguments: [draft.title, now, draft.id]
        )

        try softDeleteRemovedExercises(draft: draft, now: now, in: db)

        for exercise in draft.exercises {
            try upsertExercise(exercise, sessionID: draft.id, now: now, in: db)
            try softDeleteRemovedSets(exercise: exercise, now: now, in: db)
            for set in exercise.sets {
                try upsertSet(set, exercise: exercise, now: now, in: db)
            }
        }

        try ActiveSessionRepository.recomputeSessionCaches(db: db, sessionID: draft.id, now: now)
    }

    private static func softDeleteRemovedExercises(draft: WorkoutSessionDraft, now: String, in db: Database) throws {
        let existingExerciseRows = try Row.fetchAll(
            db,
            sql: "SELECT id FROM workout_session_exercise WHERE workout_session_id = ? AND deleted_at IS NULL",
            arguments: [draft.id]
        )
        let incomingExerciseIDs = Set(draft.exercises.map(\.id))

        for row in existingExerciseRows {
            let exerciseID: String = row["id"]
            guard !incomingExerciseIDs.contains(exerciseID) else { continue }
            try db.execute(
                sql: "UPDATE set_entry SET deleted_at = ? WHERE workout_session_exercise_id = ?",
                arguments: [now, exerciseID]
            )
            try db.execute(
                sql: "UPDATE workout_session_exercise SET deleted_at = ? WHERE id = ?",
                arguments: [now, exerciseID]
            )
        }
    }

    private static func upsertExercise(
        _ exercise: WorkoutSessionExerciseDraft,
        sessionID: String,
        now: String,
        in db: Database
    ) throws {
        let exists = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM workout_session_exercise WHERE id = ? AND deleted_at IS NULL",
            arguments: [exercise.id]
        ) ?? 0

        if exists > 0 {
            try db.execute(
                sql: """
                    UPDATE workout_session_exercise
                    SET display_order = ?, exercise_mode = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [exercise.displayOrder, exercise.exerciseMode.rawValue, now, exercise.id]
            )
        } else {
            try db.execute(
                sql: """
                    INSERT INTO workout_session_exercise (
                        id, workout_session_id, exercise_id, display_order, exercise_mode,
                        target_rest_seconds, is_collapsed, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, 90, 0, ?, ?)
                    """,
                arguments: [
                    exercise.id, sessionID, exercise.exerciseID, exercise.displayOrder,
                    exercise.exerciseMode.rawValue, now, now
                ]
            )
        }
    }

    private static func softDeleteRemovedSets(
        exercise: WorkoutSessionExerciseDraft,
        now: String,
        in db: Database
    ) throws {
        let existingSetRows = try Row.fetchAll(
            db,
            sql: "SELECT id FROM set_entry WHERE workout_session_exercise_id = ? AND deleted_at IS NULL",
            arguments: [exercise.id]
        )
        let incomingSetIDs = Set(exercise.sets.map(\.id))

        for setRow in existingSetRows {
            let setID: String = setRow["id"]
            guard !incomingSetIDs.contains(setID) else { continue }
            try db.execute(
                sql: "UPDATE set_entry SET deleted_at = ? WHERE id = ?",
                arguments: [now, setID]
            )
        }
    }

    private static func upsertSet(
        _ set: SetEntryDraft,
        exercise: WorkoutSessionExerciseDraft,
        now: String,
        in db: Database
    ) throws {
        let setExists = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM set_entry WHERE id = ? AND deleted_at IS NULL",
            arguments: [set.id]
        ) ?? 0

        if setExists > 0 {
            try db.execute(
                sql: """
                    UPDATE set_entry
                    SET set_index = ?, set_type = ?, status = ?, weight_kg = ?, reps = ?,
                        distance_km = ?, duration_seconds = ?, rpe = ?, rir = ?,
                        logged_exercise_id = ?, completed_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    set.setIndex,
                    set.setType.rawValue,
                    set.status.rawValue,
                    set.mass?.kilograms,
                    set.reps,
                    set.distanceKilometers,
                    set.durationSeconds,
                    set.rpe,
                    set.rir,
                    exercise.exerciseID,
                    set.completedAt.map(ISO8601Coding.string(from:)),
                    now,
                    set.id
                ]
            )
        } else {
            try db.execute(
                sql: """
                    INSERT INTO set_entry (
                        id, workout_session_exercise_id, logged_exercise_id,
                        set_index, set_type, status, weight_kg, reps, distance_km,
                        duration_seconds, rpe, rir, completed_at, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    set.id,
                    exercise.id,
                    exercise.exerciseID,
                    set.setIndex,
                    set.setType.rawValue,
                    set.status.rawValue,
                    set.mass?.kilograms,
                    set.reps,
                    set.distanceKilometers,
                    set.durationSeconds,
                    set.rpe,
                    set.rir,
                    set.completedAt.map(ISO8601Coding.string(from:)),
                    now,
                    now
                ]
            )
        }
    }
}
