import Core
import Foundation

public struct SessionAdjustmentPayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let reply: String
    public let rationale: String?
    public let operations: [SessionAdjustmentOperation]

    /// v2 and unified initializer.
    public init(
        schemaVersion: String,
        reply: String,
        rationale: String? = nil,
        operations: [SessionAdjustmentOperation]
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
        self.rationale = rationale
        self.operations = operations
    }

    /// v1 compatibility: rationale doubles as chat reply.
    public init(
        schemaVersion: String,
        rationale: String,
        operations: [SessionAdjustmentOperation]
    ) {
        self.init(
            schemaVersion: schemaVersion,
            reply: rationale,
            rationale: rationale,
            operations: operations
        )
    }

    public var bannerReason: String {
        rationale ?? reply
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        operations = try container.decode([SessionAdjustmentOperation].self, forKey: .operations)

        if let decodedReply = try container.decodeIfPresent(String.self, forKey: .reply) {
            reply = decodedReply
            rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        } else {
            let legacyRationale = try container.decode(String.self, forKey: .rationale)
            reply = legacyRationale
            rationale = legacyRationale
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(reply, forKey: .reply)
        try container.encodeIfPresent(rationale, forKey: .rationale)
        try container.encode(operations, forKey: .operations)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reply
        case rationale
        case operations
    }
}

public struct SessionAdjustmentOperation: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case swap
        case reorder
        case adjustSets
        case adjustWarmupSets
        case adjustLoad
        case adjustRPE
        case addExercise
    }

    public let kind: Kind
    public let fromExerciseID: String?
    public let toExerciseID: String?
    public let excludeExerciseIDs: [String]?
    public let orderedExerciseIDs: [String]?
    public let exerciseID: String?
    public let setDelta: Int?
    public let massDeltaKg: Double?
    public let targetMassKg: Double?
    public let rpeDelta: Double?
    public let targetRPE: Double?
    public let loadAdjustmentIntent: LoadAdjustmentIntent?
    public let targetSets: Int?
    public let warmupSets: Int?

    public init(
        kind: Kind,
        fromExerciseID: String? = nil,
        toExerciseID: String? = nil,
        excludeExerciseIDs: [String]? = nil,
        orderedExerciseIDs: [String]? = nil,
        exerciseID: String? = nil,
        setDelta: Int? = nil,
        massDeltaKg: Double? = nil,
        targetMassKg: Double? = nil,
        rpeDelta: Double? = nil,
        targetRPE: Double? = nil,
        loadAdjustmentIntent: LoadAdjustmentIntent? = nil,
        targetSets: Int? = nil,
        warmupSets: Int? = nil
    ) {
        self.kind = kind
        self.fromExerciseID = fromExerciseID
        self.toExerciseID = toExerciseID
        self.excludeExerciseIDs = excludeExerciseIDs
        self.orderedExerciseIDs = orderedExerciseIDs
        self.exerciseID = exerciseID
        self.setDelta = setDelta
        self.massDeltaKg = massDeltaKg
        self.targetMassKg = targetMassKg
        self.rpeDelta = rpeDelta
        self.targetRPE = targetRPE
        self.loadAdjustmentIntent = loadAdjustmentIntent
        self.targetSets = targetSets
        self.warmupSets = warmupSets
    }
}

public struct MealEstimatePayload: Codable, Sendable, Equatable {
    public enum Confidence: String, Codable, Sendable, Equatable {
        case low
        case medium
        case high
    }

    public let schemaVersion: String
    public let description: String
    public let caloriesKcal: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let confidence: Confidence

    public init(
        schemaVersion: String,
        description: String,
        caloriesKcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        confidence: Confidence
    ) {
        self.schemaVersion = schemaVersion
        self.description = description
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.confidence = confidence
    }
}

public struct MealDecompositionPayload: Codable, Sendable, Equatable {
    public enum Confidence: String, Codable, Sendable, Equatable {
        case low
        case medium
        case high
    }

    public struct Item: Codable, Sendable, Equatable {
        public let name: String
        public let estimatedGrams: Double
        public let confidence: Confidence

        public init(name: String, estimatedGrams: Double, confidence: Confidence) {
            self.name = name
            self.estimatedGrams = estimatedGrams
            self.confidence = confidence
        }
    }

    public let schemaVersion: String
    public let mealDescription: String
    public let items: [Item]
    public let implicitFats: [Item]
    public let portionNotes: String?

    public init(
        schemaVersion: String,
        mealDescription: String,
        items: [Item],
        implicitFats: [Item] = [],
        portionNotes: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.mealDescription = mealDescription
        self.items = items
        self.implicitFats = implicitFats
        self.portionNotes = portionNotes
    }
}

public struct MealDecomposition: Sendable, Equatable {
    public let mealDescription: String
    public let items: [MealDecompositionPayload.Item]
    public let implicitFats: [MealDecompositionPayload.Item]
    public let portionNotes: String?

    public init(payload: MealDecompositionPayload) {
        mealDescription = payload.mealDescription
        items = payload.items
        implicitFats = payload.implicitFats
        portionNotes = payload.portionNotes
    }
}

public struct FoodLogPayload: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable, Equatable {
        case log
        case edit
        case delete

        public init?(rawFlexible value: String) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "log", "add", "create":
                self = .log
            case "edit", "update":
                self = .edit
            case "delete", "remove":
                self = .delete
            default:
                return nil
            }
        }
    }

    public let schemaVersion: String
    public let reply: String
    public let action: Action
    public let mealID: String?
    public let description: String?
    public let bucket: String?
    public let caloriesKcal: Double?
    public let proteinG: Double?
    public let carbsG: Double?
    public let fatG: Double?
    public let helmDay: String?
    public let items: [MealDecompositionPayload.Item]?
    public let implicitFats: [MealDecompositionPayload.Item]?
    public let portionNotes: String?

    public var hasIngredientBreakdown: Bool {
        !(items ?? []).isEmpty
    }

    public init(
        schemaVersion: String,
        reply: String,
        action: Action,
        mealID: String? = nil,
        description: String? = nil,
        bucket: String? = nil,
        caloriesKcal: Double? = nil,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatG: Double? = nil,
        helmDay: String? = nil,
        items: [MealDecompositionPayload.Item]? = nil,
        implicitFats: [MealDecompositionPayload.Item]? = nil,
        portionNotes: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
        self.action = action
        self.mealID = mealID
        self.description = description
        self.bucket = bucket
        self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.helmDay = helmDay
        self.items = items
        self.implicitFats = implicitFats
        self.portionNotes = portionNotes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        reply = try container.decodeIfPresent(String.self, forKey: .reply) ?? ""

        if let decoded = try? container.decode(Action.self, forKey: .action) {
            action = decoded
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .action),
                  let flexible = Action(rawFlexible: raw) {
            action = flexible
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .action,
                in: container,
                debugDescription: "food_log.v1 action must be log, edit, or delete"
            )
        }

        mealID = try container.decodeIfPresent(String.self, forKey: .mealID)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket)
        caloriesKcal = try Self.decodeFlexibleDouble(from: container, forKey: .caloriesKcal)
        proteinG = try Self.decodeFlexibleDouble(from: container, forKey: .proteinG)
        carbsG = try Self.decodeFlexibleDouble(from: container, forKey: .carbsG)
        fatG = try Self.decodeFlexibleDouble(from: container, forKey: .fatG)
        helmDay = try container.decodeIfPresent(String.self, forKey: .helmDay)
        items = try container.decodeIfPresent([MealDecompositionPayload.Item].self, forKey: .items)
        implicitFats = try container.decodeIfPresent([MealDecompositionPayload.Item].self, forKey: .implicitFats)
        portionNotes = try container.decodeIfPresent(String.self, forKey: .portionNotes)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reply
        case action
        case mealID
        case description
        case bucket
        case caloriesKcal
        case proteinG
        case carbsG
        case fatG
        case helmDay
        case items
        case implicitFats
        case portionNotes
    }

    private static func decodeFlexibleDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Double? {
        if !container.contains(key) {
            return nil
        }
        if try container.decodeNil(forKey: key) {
            return nil
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int.self, forKey: key) {
            return Double(value)
        }
        if let raw = try? container.decode(String.self, forKey: key) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if let value = Double(trimmed) {
                return value
            }
        }
        throw DecodingError.typeMismatch(
            Double.self,
            DecodingError.Context(
                codingPath: container.codingPath + [key],
                debugDescription: "Expected number or numeric string for \(key.stringValue)"
            )
        )
    }
}

public struct MorningBriefPayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let narration: String
    public let citationIDs: [String]

    public init(schemaVersion: String, narration: String, citationIDs: [String]) {
        self.schemaVersion = schemaVersion
        self.narration = narration
        self.citationIDs = citationIDs
    }
}

/// Coach-rendered chart for chat when the athlete asks for a visual.
public struct ChartPayload: Codable, Sendable, Equatable {
    public struct Point: Codable, Sendable, Equatable, Identifiable {
        public var id: String { "\(label)-\(value)" }
        public let label: String
        public let value: Double

        public init(label: String, value: Double) {
            self.label = label
            self.value = value
        }
    }

    public let schemaVersion: String
    public let reply: String
    public let title: String
    public let unit: String?
    public let points: [Point]

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.chartV1.rawValue,
        reply: String,
        title: String,
        unit: String? = nil,
        points: [Point]
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
        self.title = title
        self.unit = unit
        self.points = points
    }
}

public enum ChartPayloadParser: Sendable {
    public static func parse(from text: String) -> ChartPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .chartV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ChartPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.chartV1.rawValue,
              !payload.points.isEmpty
        else {
            return nil
        }
        return payload
    }
}

/// Shared decoding surface for the `*_query.v1` payload coding-key enums.
private protocol CoachQueryPayloadCodingKeys: CodingKey {
    static var schemaVersionKey: Self { get }
    static var queryTypeKey: Self { get }
    static var lookbackDaysKey: Self { get }
}

private extension KeyedDecodingContainer where Key: CoachQueryPayloadCodingKeys {
    func decodeSchemaVersion() throws -> String {
        try decode(String.self, forKey: .schemaVersionKey)
    }

    func decodeFlexibleQueryType<T: Decodable>(
        flexible: (String) -> T?,
        context: String,
        allowedValues: String
    ) throws -> T {
        if let decoded = try? decode(T.self, forKey: .queryTypeKey) {
            return decoded
        }
        if let raw = try decodeIfPresent(String.self, forKey: .queryTypeKey),
           let result = flexible(raw) {
            return result
        }
        throw DecodingError.dataCorruptedError(
            forKey: .queryTypeKey,
            in: self,
            debugDescription: "\(context) queryType must be \(allowedValues)"
        )
    }

    func decodeLenientLookbackDays() -> Int? {
        if let intValue = try? decodeIfPresent(Int.self, forKey: .lookbackDaysKey) {
            return intValue
        }
        if let raw = try? decodeIfPresent(String.self, forKey: .lookbackDaysKey),
           let intValue = Int(raw) {
            return intValue
        }
        return nil
    }
}

public struct MealQueryPayload: Codable, Sendable, Equatable {
    public enum QueryType: String, Codable, Sendable, Equatable {
        case bucketOnDay
        case usualForBucket
        case daySummary

        public init?(rawFlexible value: String) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "bucketonday", "bucket_on_day", "on_day", "day_bucket":
                self = .bucketOnDay
            case "usualforbucket", "usual_for_bucket", "usual", "typical":
                self = .usualForBucket
            case "daysummary", "day_summary", "summary":
                self = .daySummary
            default:
                return nil
            }
        }
    }

    public let schemaVersion: String
    public let queryType: QueryType
    public let helmDay: String?
    public let bucket: String?
    public let lookbackDays: Int?

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.mealQueryV1.rawValue,
        queryType: QueryType,
        helmDay: String? = nil,
        bucket: String? = nil,
        lookbackDays: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.queryType = queryType
        self.helmDay = helmDay
        self.bucket = bucket
        self.lookbackDays = lookbackDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeSchemaVersion()
        queryType = try container.decodeFlexibleQueryType(
            flexible: QueryType.init(rawFlexible:),
            context: "meal_query.v1",
            allowedValues: "bucketOnDay, usualForBucket, or daySummary"
        )
        helmDay = try container.decodeIfPresent(String.self, forKey: .helmDay)
        bucket = try container.decodeIfPresent(String.self, forKey: .bucket)
        lookbackDays = container.decodeLenientLookbackDays()
    }

    private enum CodingKeys: String, CodingKey, CoachQueryPayloadCodingKeys {
        case schemaVersion
        case queryType
        case helmDay
        case bucket
        case lookbackDays

        static var schemaVersionKey: CodingKeys { .schemaVersion }
        static var queryTypeKey: CodingKeys { .queryType }
        static var lookbackDaysKey: CodingKeys { .lookbackDays }
    }
}

public struct MealCopyPayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let reply: String
    public let sourceHelmDay: String
    public let sourceBucket: String
    public let targetHelmDay: String
    public let targetBucket: String

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.mealCopyV1.rawValue,
        reply: String,
        sourceHelmDay: String,
        sourceBucket: String,
        targetHelmDay: String,
        targetBucket: String
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
        self.sourceHelmDay = sourceHelmDay
        self.sourceBucket = sourceBucket
        self.targetHelmDay = targetHelmDay
        self.targetBucket = targetBucket
    }
}

public enum MealQueryPayloadParser: Sendable {
    public static func parse(from text: String) -> MealQueryPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .mealQueryV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(MealQueryPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.mealQueryV1.rawValue
        else {
            return nil
        }
        return payload
    }
}

public enum MealCopyPayloadParser: Sendable {
    public static func parse(from text: String) -> MealCopyPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .mealCopyV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(MealCopyPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.mealCopyV1.rawValue
        else {
            return nil
        }
        return payload
    }
}

public struct WorkoutQueryPayload: Codable, Sendable, Equatable {
    public enum QueryType: String, Codable, Sendable, Equatable {
        case latestCompleted
        case onDay
        case includingCardio

        public init?(rawFlexible value: String) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "latestcompleted", "latest_completed", "latest", "last":
                self = .latestCompleted
            case "onday", "on_day", "day":
                self = .onDay
            case "includingcardio", "including_cardio", "cardio", "with_run":
                self = .includingCardio
            default:
                return nil
            }
        }
    }

    public let schemaVersion: String
    public let queryType: QueryType
    public let helmDay: String?
    public let lookbackDays: Int?

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.workoutQueryV1.rawValue,
        queryType: QueryType,
        helmDay: String? = nil,
        lookbackDays: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.queryType = queryType
        self.helmDay = helmDay
        self.lookbackDays = lookbackDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeSchemaVersion()
        queryType = try container.decodeFlexibleQueryType(
            flexible: QueryType.init(rawFlexible:),
            context: "workout_query.v1",
            allowedValues: "latestCompleted, onDay, or includingCardio"
        )
        helmDay = try container.decodeIfPresent(String.self, forKey: .helmDay)
        lookbackDays = container.decodeLenientLookbackDays()
    }

    private enum CodingKeys: String, CodingKey, CoachQueryPayloadCodingKeys {
        case schemaVersion
        case queryType
        case helmDay
        case lookbackDays

        static var schemaVersionKey: CodingKeys { .schemaVersion }
        static var queryTypeKey: CodingKeys { .queryType }
        static var lookbackDaysKey: CodingKeys { .lookbackDays }
    }
}

public enum WorkoutQueryPayloadParser: Sendable {
    public static func parse(from text: String) -> WorkoutQueryPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .workoutQueryV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(WorkoutQueryPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.workoutQueryV1.rawValue
        else {
            return nil
        }
        return payload
    }
}

public struct RecoveryQueryPayload: Codable, Sendable, Equatable {
    public enum QueryType: String, Codable, Sendable, Equatable {
        case today
        case day
        case range
        case sleepDetail

        public init?(rawFlexible value: String) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "today", "now", "current":
                self = .today
            case "day", "onday", "on_day":
                self = .day
            case "range", "history", "trend", "trends":
                self = .range
            case "sleepdetail", "sleep_detail", "sleep", "stages":
                self = .sleepDetail
            default:
                return nil
            }
        }
    }

    public let schemaVersion: String
    public let queryType: QueryType
    public let helmDay: String?
    public let lookbackDays: Int?

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.recoveryQueryV1.rawValue,
        queryType: QueryType,
        helmDay: String? = nil,
        lookbackDays: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.queryType = queryType
        self.helmDay = helmDay
        self.lookbackDays = lookbackDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeSchemaVersion()
        queryType = try container.decodeFlexibleQueryType(
            flexible: QueryType.init(rawFlexible:),
            context: "recovery_query.v1",
            allowedValues: "today, day, range, or sleepDetail"
        )
        helmDay = try container.decodeIfPresent(String.self, forKey: .helmDay)
        lookbackDays = container.decodeLenientLookbackDays()
    }

    private enum CodingKeys: String, CodingKey, CoachQueryPayloadCodingKeys {
        case schemaVersion
        case queryType
        case helmDay
        case lookbackDays

        static var schemaVersionKey: CodingKeys { .schemaVersion }
        static var queryTypeKey: CodingKeys { .queryType }
        static var lookbackDaysKey: CodingKeys { .lookbackDays }
    }
}

public enum RecoveryQueryPayloadParser: Sendable {
    public static func parse(from text: String) -> RecoveryQueryPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .recoveryQueryV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(RecoveryQueryPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.recoveryQueryV1.rawValue
        else {
            return nil
        }
        return payload
    }
}

public struct CalendarQueryPayload: Codable, Sendable, Equatable {
    public enum QueryType: String, Codable, Sendable, Equatable {
        case today
        case day
        case range
        case weekAhead

        public init?(rawFlexible value: String) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "today", "now", "current":
                self = .today
            case "day", "onday", "on_day":
                self = .day
            case "range", "history", "week":
                self = .range
            case "weekahead", "week_ahead", "ahead", "schedule":
                self = .weekAhead
            default:
                return nil
            }
        }
    }

    public let schemaVersion: String
    public let queryType: QueryType
    public let helmDay: String?
    public let lookbackDays: Int?

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.calendarQueryV1.rawValue,
        queryType: QueryType,
        helmDay: String? = nil,
        lookbackDays: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.queryType = queryType
        self.helmDay = helmDay
        self.lookbackDays = lookbackDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeSchemaVersion()
        queryType = try container.decodeFlexibleQueryType(
            flexible: QueryType.init(rawFlexible:),
            context: "calendar_query.v1",
            allowedValues: "today, day, range, or weekAhead"
        )
        helmDay = try container.decodeIfPresent(String.self, forKey: .helmDay)
        lookbackDays = container.decodeLenientLookbackDays()
    }

    private enum CodingKeys: String, CodingKey, CoachQueryPayloadCodingKeys {
        case schemaVersion
        case queryType
        case helmDay
        case lookbackDays

        static var schemaVersionKey: CodingKeys { .schemaVersion }
        static var queryTypeKey: CodingKeys { .queryType }
        static var lookbackDaysKey: CodingKeys { .lookbackDays }
    }
}

public enum CalendarQueryPayloadParser: Sendable {
    public static func parse(from text: String) -> CalendarQueryPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .calendarQueryV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CalendarQueryPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.calendarQueryV1.rawValue
        else {
            return nil
        }
        return payload
    }
}

public struct TrendsQueryPayload: Codable, Sendable, Equatable {
    public enum QueryType: String, Codable, Sendable, Equatable {
        case trimp
        case weight
        case e1rm
        case energyBalance
        case readiness
        case all

        public init?(rawFlexible value: String) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "trimp", "training_load", "strain", "load":
                self = .trimp
            case "weight", "body_weight", "scale", "trend_weight":
                self = .weight
            case "e1rm", "e1rm_progression", "strength", "progression":
                self = .e1rm
            case "energybalance", "energy_balance", "balance", "calories":
                self = .energyBalance
            case "readiness", "readiness_history", "scores":
                self = .readiness
            case "all", "everything", "overview":
                self = .all
            default:
                return nil
            }
        }
    }

    public let schemaVersion: String
    public let queryType: QueryType
    public let exerciseName: String?
    public let lookbackDays: Int?

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.trendsQueryV1.rawValue,
        queryType: QueryType,
        exerciseName: String? = nil,
        lookbackDays: Int? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.queryType = queryType
        self.exerciseName = exerciseName
        self.lookbackDays = lookbackDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeSchemaVersion()
        queryType = try container.decodeFlexibleQueryType(
            flexible: QueryType.init(rawFlexible:),
            context: "trends_query.v1",
            allowedValues: "trimp, weight, e1rm, energyBalance, readiness, or all"
        )
        exerciseName = try container.decodeIfPresent(String.self, forKey: .exerciseName)
        lookbackDays = container.decodeLenientLookbackDays()
    }

    private enum CodingKeys: String, CodingKey, CoachQueryPayloadCodingKeys {
        case schemaVersion
        case queryType
        case exerciseName
        case lookbackDays

        static var schemaVersionKey: CodingKeys { .schemaVersion }
        static var queryTypeKey: CodingKeys { .queryType }
        static var lookbackDaysKey: CodingKeys { .lookbackDays }
    }
}

public enum TrendsQueryPayloadParser: Sendable {
    public static func parse(from text: String) -> TrendsQueryPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .trendsQueryV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TrendsQueryPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.trendsQueryV1.rawValue
        else {
            return nil
        }
        return payload
    }
}

public enum CoachChatChartSnapshot: Sendable {
    public static func text(for payload: ChartPayload) -> String {
        var lines = [
            "# Chart",
            "## Title",
            payload.title,
            "## Unit",
            payload.unit ?? "none",
            "## Points"
        ]
        for point in payload.points {
            lines.append("- \(point.label)=\(formatValue(point.value))")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatValue(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

public struct SettingsAdjustmentPayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let phase: String?
    public let weeklyRateKg: Double?
    public let emphasis: String?
    public let rationale: String?
    public let reply: String?

    public init(
        schemaVersion: String,
        phase: String? = nil,
        weeklyRateKg: Double? = nil,
        emphasis: String? = nil,
        rationale: String? = nil,
        reply: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.phase = phase
        self.weeklyRateKg = weeklyRateKg
        self.emphasis = emphasis
        self.rationale = rationale
        self.reply = reply
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        phase = try container.decodeIfPresent(String.self, forKey: .phase)
        weeklyRateKg = try container.decodeIfPresent(Double.self, forKey: .weeklyRateKg)
        emphasis = try container.decodeIfPresent(String.self, forKey: .emphasis)
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale)
        reply = try container.decodeIfPresent(String.self, forKey: .reply)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, phase, weeklyRateKg, emphasis, rationale, reply
    }
}

public enum SettingsAdjustmentPayloadParser: Sendable {
    public static func parse(from text: String) -> SettingsAdjustmentPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .settingsAdjustmentV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SettingsAdjustmentPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.settingsAdjustmentV1.rawValue
        else {
            return nil
        }
        return payload
    }
}

public struct ReactiveDeloadPayload: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable, Equatable {
        case confirm
        case dismiss
    }

    public let schemaVersion: String
    public let action: Action
    public let reply: String

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.reactiveDeloadV1.rawValue,
        action: Action,
        reply: String
    ) {
        self.schemaVersion = schemaVersion
        self.action = action
        self.reply = reply
    }
}

public enum ReactiveDeloadPayloadParser: Sendable {
    public static func parse(from text: String) -> ReactiveDeloadPayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .reactiveDeloadV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ReactiveDeloadPayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.reactiveDeloadV1.rawValue
        else {
            return nil
        }
        return payload
    }
}

public struct PlanRegeneratePayload: Codable, Sendable, Equatable {
    public let schemaVersion: String
    public let reply: String

    public init(
        schemaVersion: String = CoachOutputSchemaVersion.planRegenerateV1.rawValue,
        reply: String
    ) {
        self.schemaVersion = schemaVersion
        self.reply = reply
    }
}

public enum PlanRegeneratePayloadParser: Sendable {
    public static func parse(from text: String) -> PlanRegeneratePayload? {
        guard let block = CoachEmbeddedJSONBlockFinder.firstBlock(in: text, matching: .planRegenerateV1),
              let data = block.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PlanRegeneratePayload.self, from: data),
              payload.schemaVersion == CoachOutputSchemaVersion.planRegenerateV1.rawValue
        else {
            return nil
        }
        return payload
    }
}

public struct CalendarEventClassifyPayload: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let title: String
        public let classification: String

        public init(title: String, classification: String) {
            self.title = title
            self.classification = classification
        }
    }

    public let classifications: [Entry]

    public init(classifications: [Entry]) {
        self.classifications = classifications
    }
}
