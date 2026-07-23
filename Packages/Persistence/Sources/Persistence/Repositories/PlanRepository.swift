import Core
import Foundation
import GRDB

public struct PlanRepository: Sendable {
    private let pool: DatabasePool

    init(pool: DatabasePool) {
        self.pool = pool
    }

    public func loadMesocycleStateJSON() throws -> String? {
        try pool.read { db in
            try PlanMesocycleRecord.fetchOne(db, key: PlanMesocycleRecord.singletonID)?.stateJSON
        }
    }

    public func saveMesocycleStateJSON(_ json: String, updatedAt: Date = Date()) throws {
        try pool.write { db in
            try PlanMesocycleRecord(stateJSON: json, updatedAt: updatedAt).save(db)
        }
    }

    public func fetchPlannedWorkouts(from start: HelmDay, through end: HelmDay) throws -> [PlannedWorkoutRecord] {
        try pool.read { db in
            try PlannedWorkoutRecord
                .filter(Column("helm_day") >= HelmDayColumn.encode(start))
                .filter(Column("helm_day") <= HelmDayColumn.encode(end))
                .order(Column("helm_day"))
                .fetchAll(db)
        }
    }

    public func replacePlannedWorkouts(_ workouts: [PlannedWorkoutRecord]) throws {
        try pool.write { db in
            try PlannedWorkoutRecord.deleteAll(db)
            for workout in workouts {
                try workout.insert(db)
            }
        }
    }
}
