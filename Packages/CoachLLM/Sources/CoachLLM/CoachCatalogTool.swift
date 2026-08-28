import Foundation

/// Provider-neutral catalog tools. Each LLM adapter maps these names
/// into its native tool format (Gemini functionDeclarations, OpenRouter tools, etc).
public enum CoachCatalogToolName: String, Sendable, CaseIterable {
    case foodLog = "food_log"
    case mealCopy = "meal_copy"
    case workoutStart = "workout_start"
    case memoryAdjustment = "memory_adjustment"
    case settingsAdjustment = "settings_adjustment"
    case reactiveDeload = "reactive_deload"
    case planRegenerate = "plan_regenerate"
    case mealQuery = "meal_query"
    case recoveryQuery = "recovery_query"
    case calendarQuery = "calendar_query"
    case trendsQuery = "trends_query"
    case workoutQuery = "workout_query"
    case nutritionQuery = "nutrition_query"

    public var schemaVersion: CoachOutputSchemaVersion {
        switch self {
        case .foodLog: .foodLogV1
        case .mealCopy: .mealCopyV1
        case .workoutStart: .workoutStartV2
        case .memoryAdjustment: .memoryAdjustmentV1
        case .settingsAdjustment: .settingsAdjustmentV1
        case .reactiveDeload: .reactiveDeloadV1
        case .planRegenerate: .planRegenerateV1
        case .mealQuery: .mealQueryV1
        case .recoveryQuery: .recoveryQueryV1
        case .calendarQuery: .calendarQueryV1
        case .trendsQuery: .trendsQueryV1
        case .workoutQuery: .workoutQueryV1
        case .nutritionQuery: .nutritionQueryV1
        }
    }

    /// Writes become confirm cards. Queries run immediately and feed a follow-up turn.
    public var isQuery: Bool {
        switch self {
        case .mealQuery, .recoveryQuery, .calendarQuery, .trendsQuery, .workoutQuery, .nutritionQuery:
            true
        default:
            false
        }
    }

    public var isWrite: Bool { !isQuery }

    public static func hasWrite(in calls: [CoachLLMFunctionCall]) -> Bool {
        calls.contains { CoachCatalogToolName(rawValue: $0.name)?.isWrite == true }
    }
}

/// Decodes read-only catalog tool args into existing query payloads.
public enum CoachCatalogQueryDecoder {
    public static func meal(from calls: [CoachLLMFunctionCall]) -> MealQueryPayload? {
        decode(MealQueryPayload.self, named: .mealQuery, from: calls)
    }

    public static func recovery(from calls: [CoachLLMFunctionCall]) -> RecoveryQueryPayload? {
        decode(RecoveryQueryPayload.self, named: .recoveryQuery, from: calls)
    }

    public static func calendar(from calls: [CoachLLMFunctionCall]) -> CalendarQueryPayload? {
        decode(CalendarQueryPayload.self, named: .calendarQuery, from: calls)
    }

    public static func trends(from calls: [CoachLLMFunctionCall]) -> TrendsQueryPayload? {
        decode(TrendsQueryPayload.self, named: .trendsQuery, from: calls)
    }

    public static func workout(from calls: [CoachLLMFunctionCall]) -> WorkoutQueryPayload? {
        decode(WorkoutQueryPayload.self, named: .workoutQuery, from: calls)
    }

    public static func nutrition(from calls: [CoachLLMFunctionCall]) -> NutritionQueryPayload? {
        decode(NutritionQueryPayload.self, named: .nutritionQuery, from: calls)
    }

    public static func decode<Payload: Decodable>(
        _ type: Payload.Type,
        named name: CoachCatalogToolName,
        from calls: [CoachLLMFunctionCall]
    ) -> Payload? {
        for call in calls where call.name == name.rawValue {
            if let payload = try? call.decode(type, schemaVersion: name.schemaVersion) {
                return payload
            }
        }
        return nil
    }
}
