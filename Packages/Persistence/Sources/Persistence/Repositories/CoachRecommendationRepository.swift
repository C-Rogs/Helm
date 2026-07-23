import Core
import Foundation
import GRDB

public struct CoachRecommendationRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func insert(_ insert: CoachRecommendationInsert, generatedAt: Date = Date()) throws -> StoredCoachRecommendation {
        let id = UUID().uuidString.lowercased()
        let now = ISO8601Coding.string(from: generatedAt)
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO coach_recommendation (
                        id, scope, workout_session_id, workout_session_exercise_id, set_entry_id,
                        recommendation_type, payload_json, confidence, model_version,
                        generated_at, acted_on_at, dismissed_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)
                    """,
                arguments: [
                    id,
                    insert.scope.rawValue,
                    insert.workoutSessionID,
                    insert.workoutSessionExerciseID,
                    insert.setEntryID,
                    insert.recommendationType.rawValue,
                    insert.payloadJSON,
                    insert.confidence,
                    insert.modelVersion,
                    now
                ]
            )
        }
        return StoredCoachRecommendation(
            id: id,
            scope: insert.scope,
            workoutSessionID: insert.workoutSessionID,
            workoutSessionExerciseID: insert.workoutSessionExerciseID,
            setEntryID: insert.setEntryID,
            recommendationType: insert.recommendationType,
            payloadJSON: insert.payloadJSON,
            confidence: insert.confidence,
            modelVersion: insert.modelVersion,
            generatedAt: generatedAt
        )
    }

    public func markActedOn(id: String, at date: Date = Date()) throws {
        let now = ISO8601Coding.string(from: date)
        try pool.write { db in
            try db.execute(
                sql: "UPDATE coach_recommendation SET acted_on_at = ? WHERE id = ?",
                arguments: [now, id]
            )
        }
    }

    public func fetch(id: String) throws -> StoredCoachRecommendation? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM coach_recommendation WHERE id = ?",
                arguments: [id]
            ) else {
                return nil
            }
            return try rowToValue(row)
        }
    }

    public func fetchForSession(sessionID: String) throws -> [StoredCoachRecommendation] {
        try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM coach_recommendation
                    WHERE workout_session_id = ?
                    ORDER BY datetime(generated_at) ASC
                    """,
                arguments: [sessionID]
            )
            return try rows.map(rowToValue)
        }
    }

    private func rowToValue(_ row: Row) throws -> StoredCoachRecommendation {
        let generatedAt = try ISO8601Coding.date(from: row["generated_at"] as String)
        let actedOnAt: Date?
        if let actedString: String = row["acted_on_at"] {
            actedOnAt = try ISO8601Coding.date(from: actedString)
        } else {
            actedOnAt = nil
        }
        let dismissedAt: Date?
        if let dismissedString: String = row["dismissed_at"] {
            dismissedAt = try ISO8601Coding.date(from: dismissedString)
        } else {
            dismissedAt = nil
        }

        return StoredCoachRecommendation(
            id: row["id"],
            scope: CoachRecommendationScope(rawValue: row["scope"] as String) ?? .session,
            workoutSessionID: row["workout_session_id"],
            workoutSessionExerciseID: row["workout_session_exercise_id"],
            setEntryID: row["set_entry_id"],
            recommendationType: CoachRecommendationType(rawValue: row["recommendation_type"] as String) ?? .sessionAdjustment,
            payloadJSON: row["payload_json"],
            confidence: row["confidence"],
            modelVersion: row["model_version"],
            generatedAt: generatedAt,
            actedOnAt: actedOnAt,
            dismissedAt: dismissedAt
        )
    }
}
