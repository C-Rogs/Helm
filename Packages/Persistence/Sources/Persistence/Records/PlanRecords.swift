import Core
import Foundation
import GRDB

struct PlanMesocycleRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "plan_mesocycle_state"

    enum CodingKeys: String, CodingKey {
        case id
        case stateJSON = "state_json"
        case updatedAt = "updated_at"
    }

    static let singletonID = 1

    var id: Int
    var stateJSON: String
    var updatedAt: String

    init(stateJSON: String, updatedAt: Date = Date()) {
        id = Self.singletonID
        self.stateJSON = stateJSON
        self.updatedAt = ISO8601Coding.string(from: updatedAt)
    }
}

public struct PlannedWorkoutRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "planned_workout"

    enum CodingKeys: String, CodingKey {
        case id
        case helmDay = "helm_day"
        case status
        case trainingLoad = "training_load"
        case sessionJSON = "session_json"
        case updatedAt = "updated_at"
    }

    public var id: String
    public var helmDay: String
    public var status: String
    public var trainingLoad: Double
    public var sessionJSON: String
    public var updatedAt: String

    public init(
        id: String,
        helmDay: HelmDay,
        status: String,
        trainingLoad: Double,
        sessionJSON: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.helmDay = HelmDayColumn.encode(helmDay)
        self.status = status
        self.trainingLoad = trainingLoad
        self.sessionJSON = sessionJSON
        self.updatedAt = ISO8601Coding.string(from: updatedAt)
    }

    public func decodedHelmDay() throws -> HelmDay {
        try HelmDayColumn.decode(helmDay)
    }
}
