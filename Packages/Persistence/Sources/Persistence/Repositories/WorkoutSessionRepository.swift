import Core
import Foundation
import GRDB

public enum WorkoutSessionHistoryScope: String, Sendable, Hashable, CaseIterable, Identifiable {
    case active
    case deleted

    public var id: String { rawValue }

    func deletedAtSQLPredicate(column: String) -> String {
        switch self {
        case .active:
            "\(column) IS NULL"
        case .deleted:
            "\(column) IS NOT NULL"
        }
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
        try previousPerformances(
            exerciseID: exerciseID,
            targets: [(setIndex: setIndex, setType: setType)],
            excludingSessionID: excludingSessionID
        ).first?.performance
    }

    /// One recent-history read per exercise; match every requested set slot in memory.
    /// Avoids N identical LIMIT-80 queries when refreshing an active session.
    public func previousPerformances(
        exerciseID: String,
        targets: [(setIndex: Int, setType: SetType)],
        excludingSessionID: String? = nil
    ) throws -> [(setIndex: Int, setType: SetType, performance: PreviousPerformance)] {
        guard !targets.isEmpty else { return [] }

        return try pool.read { db in
            let rows = try Self.fetchRecentCompletedSetRows(
                db: db,
                exerciseID: exerciseID,
                excludingSessionID: excludingSessionID
            )
            var results: [(setIndex: Int, setType: SetType, performance: PreviousPerformance)] = []
            results.reserveCapacity(targets.count)
            for target in targets {
                if let performance = try Self.matchPreviousPerformance(
                    exerciseID: exerciseID,
                    setIndex: target.setIndex,
                    setType: target.setType,
                    rows: rows
                ) {
                    results.append((target.setIndex, target.setType, performance))
                }
            }
            return results
        }
    }

    private static func fetchRecentCompletedSetRows(
        db: Database,
        exerciseID: String,
        excludingSessionID: String?
    ) throws -> [Row] {
        var arguments: [DatabaseValueConvertible] = [exerciseID]
        var excludeClause = ""
        if let excludingSessionID {
            excludeClause = "AND ws.id != ?"
            arguments.append(excludingSessionID)
        }

        return try Row.fetchAll(
            db,
            sql: """
                SELECT se.set_index, se.set_type, se.weight_kg, se.reps, se.distance_km,
                       se.duration_seconds, se.completed_at
                FROM set_entry se
                JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                JOIN workout_session ws ON ws.id = wse.workout_session_id
                WHERE se.logged_exercise_id = ?
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
    }

    private static func matchPreviousPerformance(
        exerciseID: String,
        setIndex: Int,
        setType: SetType,
        rows: [Row]
    ) throws -> PreviousPerformance? {
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

    public func estimatedOneRM(exerciseID: String, excludingSessionID: String? = nil) throws -> Mass? {
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
                    SELECT se.weight_kg, se.reps
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    JOIN workout_session ws ON ws.id = wse.workout_session_id
                    WHERE se.logged_exercise_id = ?
                      AND se.status = 'completed'
                      AND se.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                      AND ws.deleted_at IS NULL
                      AND ws.status = 'completed'
                      AND se.set_type != 'warmup'
                      AND se.weight_kg IS NOT NULL
                      AND se.reps IS NOT NULL
                      AND se.reps > 0
                      \(excludeClause)
                    """,
                arguments: StatementArguments(arguments)
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

    public func maxWeight(exerciseID: String, excludingSessionID: String? = nil) throws -> Double? {
        try pool.read { db in
            var arguments: [DatabaseValueConvertible] = [exerciseID]
            var excludeClause = ""
            if let excludingSessionID {
                excludeClause = "AND ws.id != ?"
                arguments.append(excludingSessionID)
            }

            return try Double.fetchOne(
                db,
                sql: """
                    SELECT MAX(se.weight_kg)
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    JOIN workout_session ws ON ws.id = wse.workout_session_id
                    WHERE se.logged_exercise_id = ?
                      AND se.status = 'completed'
                      AND se.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                      AND ws.deleted_at IS NULL
                      AND ws.status = 'completed'
                      AND se.set_type != 'warmup'
                      AND se.weight_kg IS NOT NULL
                      \(excludeClause)
                    """,
                arguments: StatementArguments(arguments)
            )
        }
    }

    public func maxReps(
        exerciseID: String,
        atWeightKilograms weight: Double,
        excludingSessionID: String? = nil
    ) throws -> Int? {
        try pool.read { db in
            var arguments: [DatabaseValueConvertible] = [exerciseID, weight]
            var excludeClause = ""
            if let excludingSessionID {
                excludeClause = "AND ws.id != ?"
                arguments.append(excludingSessionID)
            }

            return try Int.fetchOne(
                db,
                sql: """
                    SELECT MAX(se.reps)
                    FROM set_entry se
                    JOIN workout_session_exercise wse ON wse.id = se.workout_session_exercise_id
                    JOIN workout_session ws ON ws.id = wse.workout_session_id
                    WHERE se.logged_exercise_id = ?
                      AND se.status = 'completed'
                      AND se.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                      AND ws.deleted_at IS NULL
                      AND ws.status = 'completed'
                      AND se.set_type != 'warmup'
                      AND se.weight_kg = ?
                      AND se.reps IS NOT NULL
                      \(excludeClause)
                    """,
                arguments: StatementArguments(arguments)
            )
        }
    }

    public func listSummaries(
        limit: Int,
        offset: Int = 0,
        scope: WorkoutSessionHistoryScope = .active
    ) throws -> [WorkoutSessionSummary] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT ws.id, ws.title, ws.started_at, ws.ended_at,
                           ws.total_volume_kg_cache, ws.total_set_count_cache, ws.total_rep_count_cache,
                           ws.source,
                           ws.activity_type, ws.active_energy_kcal, ws.distance_meters,
                           (
                               SELECT COUNT(*)
                               FROM workout_session_exercise wse
                               WHERE wse.workout_session_id = ws.id AND wse.deleted_at IS NULL
                           ) AS exercise_count
                    FROM workout_session ws
                    WHERE ws.status = 'completed' AND \(scope.deletedAtSQLPredicate(column: "ws.deleted_at"))
                    ORDER BY ws.started_at DESC
                    LIMIT ? OFFSET ?
                    """,
                arguments: [limit, offset]
            )

            return try rows.map { row in
                let source = WorkoutSessionSource(rawValue: row["source"] as String) ?? .manual
                let hkActivityType: String? = row["activity_type"]
                let hkEnergy: Double? = row["active_energy_kcal"]
                let hkDistance: Double? = row["distance_meters"]

                return WorkoutSessionSummary(
                    id: row["id"],
                    title: row["title"],
                    startedAt: try ISO8601Coding.date(from: row["started_at"] as String),
                    endedAt: (row["ended_at"] as String?).flatMap { try? ISO8601Coding.date(from: $0) },
                    totalVolumeKilograms: row["total_volume_kg_cache"] ?? 0,
                    totalSetCount: row["total_set_count_cache"] ?? 0,
                    totalRepCount: row["total_rep_count_cache"] ?? 0,
                    exerciseCount: row["exercise_count"] ?? 0,
                    source: source,
                    hkActivityType: hkActivityType,
                    hkActiveEnergyKilocalories: hkEnergy,
                    hkTotalDistanceMeters: hkDistance
                )
            }
        }
    }

    public func countSummaries(scope: WorkoutSessionHistoryScope = .active) throws -> Int {
        try pool.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM workout_session
                    WHERE status = 'completed'
                      AND \(scope.deletedAtSQLPredicate(column: "deleted_at"))
                    """
            ) ?? 0
        }
    }

    public func fetch(id: String) throws -> WorkoutSessionDraft? {
        try pool.read { db in
            try Self.fetchDraft(db: db, sessionID: id, includeDeleted: true)
        }
    }

    public func fetch(ids: [String]) throws -> [String: WorkoutSessionDraft] {
        let uniqueIDs = Array(Set(ids.filter { !$0.isEmpty }))
        guard !uniqueIDs.isEmpty else { return [:] }
        let drafts = try pool.read { db in
            try Self.fetchDrafts(db: db, sessionIDs: uniqueIDs, includeDeleted: true)
        }
        return Dictionary(uniqueKeysWithValues: drafts.map { ($0.id, $0) })
    }

    public func fetchCompletedSessionsForPrescription(
        since startDay: HelmDay,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> [WorkoutSessionDraft] {
        guard let startInstant = startDay.startInstant(cutoff: cutoff, calendar: calendar) else {
            return []
        }
        return try fetchCompletedSessions(since: startInstant)
    }

    public func fetchCompletedSessions(since start: Date) throws -> [WorkoutSessionDraft] {
        let startString = ISO8601Coding.string(from: start)

        return try pool.read { db in
            let sessionIDs = try String.fetchAll(
                db,
                sql: """
                    SELECT id
                    FROM workout_session
                    WHERE status = 'completed'
                      AND deleted_at IS NULL
                      AND started_at >= ?
                    ORDER BY started_at ASC
                    """,
                arguments: [startString]
            )
            return try Self.fetchDrafts(db: db, sessionIDs: sessionIDs, includeDeleted: false)
        }
    }

    private static func fetchDrafts(
        db: Database,
        sessionIDs: [String],
        includeDeleted: Bool
    ) throws -> [WorkoutSessionDraft] {
        guard !sessionIDs.isEmpty else { return [] }
        let deletedClause = includeDeleted ? "1 = 1" : "deleted_at IS NULL"
        let sessionPlaceholders = Array(repeating: "?", count: sessionIDs.count).joined(separator: ", ")
        let headers = try Row.fetchAll(
            db,
            sql: """
                SELECT id, title, started_at, ended_at, status, source
                FROM workout_session
                WHERE id IN (\(sessionPlaceholders)) AND \(deletedClause)
                """,
            arguments: StatementArguments(sessionIDs)
        )
        guard !headers.isEmpty else { return [] }

        let foundIDs = headers.compactMap { $0["id"] as String? }
        let exercisePlaceholders = Array(repeating: "?", count: foundIDs.count).joined(separator: ", ")
        let exerciseRows = try Row.fetchAll(
            db,
            sql: """
                SELECT id, workout_session_id, exercise_id, display_order, exercise_mode, target_rest_seconds
                FROM workout_session_exercise
                WHERE workout_session_id IN (\(exercisePlaceholders)) AND deleted_at IS NULL
                ORDER BY display_order ASC
                """,
            arguments: StatementArguments(foundIDs)
        )

        var setsByExercise: [String: [Row]] = [:]
        let exerciseRowIDs = exerciseRows.compactMap { $0["id"] as String? }
        if !exerciseRowIDs.isEmpty {
            let setPlaceholders = Array(repeating: "?", count: exerciseRowIDs.count).joined(separator: ", ")
            let setRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, workout_session_exercise_id, set_index, set_type, status,
                           weight_kg, reps, distance_km, duration_seconds, rpe, rir, completed_at
                    FROM set_entry
                    WHERE workout_session_exercise_id IN (\(setPlaceholders)) AND deleted_at IS NULL
                    ORDER BY set_index ASC
                    """,
                arguments: StatementArguments(exerciseRowIDs)
            )
            setsByExercise = Dictionary(grouping: setRows) { $0["workout_session_exercise_id"] as String }
        }

        let exercisesBySession = Dictionary(grouping: exerciseRows) { $0["workout_session_id"] as String }
        let headersByID = Dictionary(uniqueKeysWithValues: headers.map { ($0["id"] as String, $0) })

        return try sessionIDs.compactMap { sessionID -> WorkoutSessionDraft? in
            guard let header = headersByID[sessionID] else { return nil }
            let exercises = try (exercisesBySession[sessionID] ?? []).map { exerciseRow throws -> WorkoutSessionExerciseDraft in
                let exerciseRowID: String = exerciseRow["id"]
                let sets = try (setsByExercise[exerciseRowID] ?? []).map { setRow throws -> SetEntryDraft in
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
                    id: exerciseRowID,
                    exerciseID: exerciseRow["exercise_id"],
                    displayOrder: exerciseRow["display_order"],
                    exerciseMode: ExerciseMode(rawValue: exerciseRow["exercise_mode"] as String) ?? .weightReps,
                    targetRestSeconds: exerciseRow["target_rest_seconds"],
                    sets: sets
                )
            }

            let status = WorkoutSessionStatus(rawValue: header["status"] as String) ?? .completed
            let source = WorkoutSessionSource(rawValue: header["source"] as String) ?? .manual

            return WorkoutSessionDraft(
                id: sessionID,
                title: header["title"],
                startedAt: try ISO8601Coding.date(from: header["started_at"] as String),
                endedAt: (header["ended_at"] as String?).flatMap { try? ISO8601Coding.date(from: $0) },
                status: status,
                source: source,
                exercises: exercises
            )
        }
    }

    private static func fetchDraft(
        db: Database,
        sessionID: String,
        includeDeleted: Bool
    ) throws -> WorkoutSessionDraft? {
        let deletedClause = includeDeleted ? "1 = 1" : "deleted_at IS NULL"
        guard let header = try Row.fetchOne(
            db,
            sql: """
                SELECT id, title, started_at, ended_at, status, source
                FROM workout_session
                WHERE id = ? AND \(deletedClause)
                """,
            arguments: [sessionID]
        ) else {
            return nil
        }

        let exercises = try ActiveSessionRepository.fetchExercises(db: db, sessionID: sessionID)
        let status = WorkoutSessionStatus(rawValue: header["status"] as String) ?? .completed
        let source = WorkoutSessionSource(rawValue: header["source"] as String) ?? .manual

        return WorkoutSessionDraft(
            id: header["id"],
            title: header["title"],
            startedAt: try ISO8601Coding.date(from: header["started_at"] as String),
            endedAt: (header["ended_at"] as String?).flatMap { try? ISO8601Coding.date(from: $0) },
            status: status,
            source: source,
            exercises: exercises
        )
    }

    public func updateCompletedSession(_ draft: WorkoutSessionDraft, timestamp: Date = Date()) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            guard let status: String = try String.fetchOne(
                db,
                sql: "SELECT status FROM workout_session WHERE id = ? AND deleted_at IS NULL",
                arguments: [draft.id]
            ), status == WorkoutSessionStatus.completed.rawValue else {
                throw PersistenceError.recordNotFound("completed session \(draft.id)")
            }

            try WorkoutSessionUpdateWriter.apply(draft, now: now, in: db)
        }
    }

    /// Soft-deletes a completed session so it no longer appears in history or trends.
    public func delete(id: String, timestamp: Date = Date()) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            guard let status: String = try String.fetchOne(
                db,
                sql: "SELECT status FROM workout_session WHERE id = ? AND deleted_at IS NULL",
                arguments: [id]
            ), status == WorkoutSessionStatus.completed.rawValue else {
                throw PersistenceError.recordNotFound("completed session \(id)")
            }

            try db.execute(
                sql: "UPDATE workout_session SET deleted_at = ?, updated_at = ? WHERE id = ?",
                arguments: [now, now, id]
            )
        }
    }

    /// Restores a soft-deleted completed session back into active history.
    public func restore(id: String, timestamp: Date = Date()) throws {
        let now = ISO8601Coding.string(from: timestamp)
        try pool.write { db in
            guard let status: String = try String.fetchOne(
                db,
                sql: """
                    SELECT status FROM workout_session
                    WHERE id = ? AND deleted_at IS NOT NULL
                    """,
                arguments: [id]
            ), status == WorkoutSessionStatus.completed.rawValue else {
                throw PersistenceError.recordNotFound("deleted session \(id)")
            }

            try db.execute(
                sql: """
                    UPDATE workout_session
                    SET deleted_at = NULL, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [now, id]
            )
        }
    }

    public struct E1RMHistoryPoint: Sendable, Hashable {
        public let helmDay: HelmDay
        public let achievedAt: Date
        public let e1RMKilograms: Double

        public init(helmDay: HelmDay, achievedAt: Date, e1RMKilograms: Double) {
            self.helmDay = helmDay
            self.achievedAt = achievedAt
            self.e1RMKilograms = e1RMKilograms
        }
    }

    /// Best estimated 1RM per completed session for one exercise, newest sessions first.
    public func fetchE1RMHistory(
        exerciseID: String,
        limit: Int,
        offset: Int = 0,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> [E1RMHistoryPoint] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT ws.started_at,
                           MAX(se.weight_kg * (1.0 + CAST(se.reps AS REAL) / 30.0)) AS e1rm_kg
                    FROM workout_session ws
                    JOIN workout_session_exercise wse ON wse.workout_session_id = ws.id
                    JOIN set_entry se ON se.workout_session_exercise_id = wse.id
                    WHERE se.logged_exercise_id = ?
                      AND ws.status = 'completed'
                      AND ws.deleted_at IS NULL
                      AND wse.deleted_at IS NULL
                      AND se.deleted_at IS NULL
                      AND se.status = 'completed'
                      AND se.set_type != 'warmup'
                      AND se.weight_kg IS NOT NULL
                      AND se.reps IS NOT NULL
                      AND se.reps > 0
                    GROUP BY ws.id
                    ORDER BY ws.started_at DESC
                    LIMIT ? OFFSET ?
                    """,
                arguments: [exerciseID, limit, offset]
            )

            return try rows.map { row in
                let startedAt = try ISO8601Coding.date(from: row["started_at"] as String)
                let e1RM: Double = row["e1rm_kg"]
                let day = HelmDay.day(for: startedAt, cutoff: cutoff, calendar: calendar)
                return E1RMHistoryPoint(
                    helmDay: day,
                    achievedAt: startedAt,
                    e1RMKilograms: e1RM
                )
            }
        }
    }

    /// Completed session IDs since a Helm day, oldest first, for paginated volume aggregation.
    public func listCompletedSessionIDs(
        since startDay: HelmDay,
        limit: Int,
        offset: Int = 0,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) throws -> [String] {
        guard let startInstant = startDay.startInstant(cutoff: cutoff, calendar: calendar) else {
            return []
        }
        let startString = ISO8601Coding.string(from: startInstant)

        return try pool.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT id
                    FROM workout_session
                    WHERE status = 'completed'
                      AND deleted_at IS NULL
                      AND started_at >= ?
                    ORDER BY started_at ASC
                    LIMIT ? OFFSET ?
                    """,
                arguments: [startString, limit, offset]
            )
        }
    }

    /// Upserts a HealthKit workout into the history table. Existing rows by `hk_uuid` are
    /// updated; deleted rows are not resurrected. Returns the stable session ID.
    public func upsertHealthKitWorkout(
        hkUUID: String,
        title: String?,
        startedAt: Date,
        endedAt: Date,
        activityType: String?,
        activeEnergyKilocalories: Double?,
        distanceMeters: Double?,
        sourceBundleID: String?,
        timestamp: Date = Date()
    ) throws -> String {
        let now = ISO8601Coding.string(from: timestamp)
        let started = ISO8601Coding.string(from: startedAt)
        let ended = ISO8601Coding.string(from: endedAt)

        return try pool.write { db in
            if let existing = try String.fetchOne(
                db,
                sql: """
                    SELECT id FROM workout_session
                    WHERE hk_uuid = ? AND deleted_at IS NULL
                    """,
                arguments: [hkUUID]
            ) {
                try db.execute(
                    sql: """
                        UPDATE workout_session
                        SET title = ?, started_at = ?, ended_at = ?,
                            activity_type = ?, active_energy_kcal = ?, distance_meters = ?,
                            source_bundle_id = ?, updated_at = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        title, started, ended,
                        activityType, activeEnergyKilocalories, distanceMeters,
                        sourceBundleID, now,
                        existing
                    ]
                )
                return existing
            }

            let sessionID = "hk_\(hkUUID)"
            try db.execute(
                sql: """
                    INSERT INTO workout_session (
                        id, title, started_at, ended_at, status, source,
                        hk_uuid, activity_type, active_energy_kcal, distance_meters,
                        source_bundle_id,
                        total_volume_kg_cache, total_set_count_cache, total_rep_count_cache,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    sessionID,
                    title,
                    started,
                    ended,
                    WorkoutSessionStatus.completed.rawValue,
                    WorkoutSessionSource.healthKit.rawValue,
                    hkUUID,
                    activityType,
                    activeEnergyKilocalories,
                    distanceMeters,
                    sourceBundleID,
                    0.0, 0, 0,
                    now,
                    now
                ]
            )
            return sessionID
        }
    }
}
