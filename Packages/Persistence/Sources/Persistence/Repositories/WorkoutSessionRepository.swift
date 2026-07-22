import Core
import Foundation
import GRDB

enum EpleyOneRepMax {
    static func estimate(mass: Mass, reps: Int) -> Mass {
        let kilograms = mass.kilograms * (1.0 + Double(reps) / 30.0)
        return Mass(kilograms: kilograms)
    }
}

public struct WorkoutSessionRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func insert(_ draft: WorkoutSessionDraft, timestamp: Date = Date()) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            var totalVolume = 0.0
            var totalSets = 0
            var totalReps = 0

            for exercise in draft.exercises {
                for set in exercise.sets where set.status == .completed {
                    totalSets += 1
                    if let reps = set.reps { totalReps += reps }
                    if let mass = set.mass, let reps = set.reps {
                        totalVolume += mass.kilograms * Double(reps)
                    }
                }
            }

            try db.execute(
                sql: """
                    INSERT INTO workout_session (
                        id, title, started_at, ended_at, status, source,
                        total_volume_kg_cache, total_set_count_cache, total_rep_count_cache,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    draft.id,
                    draft.title,
                    ISO8601Coding.string(from: draft.startedAt),
                    draft.endedAt.map(ISO8601Coding.string(from:)),
                    draft.status.rawValue,
                    draft.source.rawValue,
                    totalVolume,
                    totalSets,
                    totalReps,
                    now,
                    now
                ]
            )

            for exercise in draft.exercises {
                try db.execute(
                    sql: """
                        INSERT INTO workout_session_exercise (
                            id, workout_session_id, exercise_id, display_order, exercise_mode,
                            created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        exercise.id,
                        draft.id,
                        exercise.exerciseID,
                        exercise.displayOrder,
                        exercise.exerciseMode.rawValue,
                        now,
                        now
                    ]
                )

                for set in exercise.sets {
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
    }

    public func previousPerformance(
        exerciseID: String,
        setIndex: Int,
        setType: SetType = .normal,
        excludingSessionID: String? = nil
    ) throws -> PreviousPerformance? {
        try pool.read { db in
            var arguments: [DatabaseValueConvertible] = [exerciseID]
            var excludeClause = ""
            if let excludingSessionID {
                excludeClause = "AND ws.id != ?"
                arguments.append(excludingSessionID)
            }

            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT se.set_index, se.set_type, se.weight_kg, se.reps, se.distance_km,
                           se.duration_seconds, se.completed_at
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    JOIN workout_session ws ON ws.id = wse.workout_session_id
                    WHERE COALESCE(se.logged_exercise_id, wse.exercise_id) = ?
                      AND se.status = 'completed'
                      AND se.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                      AND ws.deleted_at IS NULL
                      AND ws.status = 'completed'
                      \(excludeClause)
                    ORDER BY se.completed_at DESC
                    LIMIT 80
                    """,
                arguments: StatementArguments(arguments)
            )

            let targetWarmup = setType.isWarmup
            func bucketMatches(_ candidate: SetType) -> Bool {
                candidate.isWarmup == targetWarmup
            }

            let match = rows.first { row in
                let candidate = SetType(rawValue: row["set_type"] as String) ?? .normal
                let index: Int = row["set_index"] ?? -1
                return bucketMatches(candidate) && index == setIndex
            } ?? rows.first { row in
                let candidate = SetType(rawValue: row["set_type"] as String) ?? .normal
                return bucketMatches(candidate)
            } ?? rows.first

            guard let match else { return nil }
            guard let completedAtString: String = match["completed_at"] else { return nil }
            let completedAt = try ISO8601Coding.date(from: completedAtString)
            let candidateType = SetType(rawValue: match["set_type"] as String) ?? .normal
            let weight: Double? = match["weight_kg"]
            let reps: Int? = match["reps"]

            return PreviousPerformance(
                exerciseID: exerciseID,
                setIndex: match["set_index"] ?? setIndex,
                setType: candidateType,
                mass: weight.map { Mass(kilograms: $0) },
                reps: reps,
                distanceKilometers: match["distance_km"],
                durationSeconds: match["duration_seconds"],
                completedAt: completedAt
            )
        }
    }

    public func estimatedOneRM(exerciseID: String) throws -> Mass? {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT se.weight_kg, se.reps
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    JOIN workout_session ws ON ws.id = wse.workout_session_id
                    WHERE COALESCE(se.logged_exercise_id, wse.exercise_id) = ?
                      AND se.status = 'completed'
                      AND se.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                      AND ws.deleted_at IS NULL
                      AND ws.status = 'completed'
                      AND se.set_type != 'warmup'
                      AND se.weight_kg IS NOT NULL
                      AND se.reps IS NOT NULL
                      AND se.reps > 0
                    """,
                arguments: [exerciseID]
            )

            return rows.compactMap { row -> Mass? in
                guard let weight: Double = row["weight_kg"],
                      let reps: Int = row["reps"],
                      reps > 0 else {
                    return nil
                }
                return EpleyOneRepMax.estimate(mass: Mass(kilograms: weight), reps: reps)
            }.max(by: { $0.kilograms < $1.kilograms })
        }
    }
}
