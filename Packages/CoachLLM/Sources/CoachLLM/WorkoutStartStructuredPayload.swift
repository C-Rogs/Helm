import Foundation

/// Gemini JSON-schema payload for chat workout starts (mirrors workout_start.v2 + reply).
public struct WorkoutStartStructuredPayload: Codable, Sendable, Equatable {
    public struct SetSpec: Codable, Sendable, Equatable {
        public let setType: String?
        public let reps: Int?
        public let massKg: Double?
        public let rpe: Double?

        public init(setType: String? = nil, reps: Int? = nil, massKg: Double? = nil, rpe: Double? = nil) {
            self.setType = setType
            self.reps = reps
            self.massKg = massKg
            self.rpe = rpe
        }
    }

    public struct ExerciseSpec: Codable, Sendable, Equatable {
        public let name: String
        public let restSeconds: Int?
        public let sets: [SetSpec]?

        public init(name: String, restSeconds: Int? = nil, sets: [SetSpec]? = nil) {
            self.name = name
            self.restSeconds = restSeconds
            self.sets = sets
        }
    }

    public let schemaVersion: String
    public let reply: String
    public let helmDay: String?
    public let title: String?
    public let useAdjustedPrescription: Bool?
    public let exercises: [ExerciseSpec]

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.workoutStartV2.rawValue,
        reply: String,
        helmDay: String? = nil,
        title: String? = nil,
        useAdjustedPrescription: Bool? = nil,
        exercises: [ExerciseSpec]
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
        self.helmDay = helmDay
        self.title = title
        self.useAdjustedPrescription = useAdjustedPrescription
        self.exercises = exercises
    }

    /// Embeddable JSON for WorkoutStartPayloadParser (schema without reply).
    public func embeddedStartJSON() throws -> String {
        var object: [String: Any] = [
            "schemaVersion": schemaVersion,
            "exercises": exercises.map { exercise -> [String: Any] in
                var item: [String: Any] = ["name": exercise.name]
                if let restSeconds = exercise.restSeconds {
                    item["restSeconds"] = restSeconds
                }
                if let sets = exercise.sets {
                    item["sets"] = sets.map { set -> [String: Any] in
                        var row: [String: Any] = [:]
                        if let setType = set.setType { row["setType"] = setType }
                        if let reps = set.reps { row["reps"] = reps }
                        if let massKg = set.massKg { row["massKg"] = massKg }
                        if let rpe = set.rpe { row["rpe"] = rpe }
                        return row
                    }
                }
                return item
            }
        ]
        if let helmDay { object["helmDay"] = helmDay }
        if let title { object["title"] = title }
        if let useAdjustedPrescription { object["useAdjustedPrescription"] = useAdjustedPrescription }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public func chatAssemblyText() throws -> String {
        let json = try embeddedStartJSON()
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return json }
        return "\(trimmed)\n\(json)"
    }
}
