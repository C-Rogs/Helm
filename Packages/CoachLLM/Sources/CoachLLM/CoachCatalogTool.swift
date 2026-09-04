import Foundation

/// Provider-neutral catalog tools. Each LLM adapter maps these names
/// into its native tool format (Gemini functionDeclarations, OpenRouter tools, etc).
public enum CoachCatalogToolName: String, Sendable, CaseIterable {
    case foodLog = "food_log"
    case mealCopy = "meal_copy"
    case workoutStart = "workout_start"
    case memoryAdjustment = "memory_adjustment"
    case settingsAdjustment = "settings_adjustment"
    case scheduleAdjustment = "schedule_adjustment"
    case reactiveDeload = "reactive_deload"
    case planRegenerate = "plan_regenerate"
    case mealQuery = "meal_query"
    case recoveryQuery = "recovery_query"
    case calendarQuery = "calendar_query"
    case trendsQuery = "trends_query"
    case patternQuery = "pattern_query"
    case workoutQuery = "workout_query"
    case nutritionQuery = "nutrition_query"
    case contextRefresh = "context_refresh"
    case healthSync = "health_sync"
    case chart = "chart"
    case navigate = "navigate"
    case workoutDiscard = "workout_discard"

    public var schemaVersion: CoachOutputSchemaVersion {
        switch self {
        case .foodLog: .foodLogV1
        case .mealCopy: .mealCopyV1
        case .workoutStart: .workoutStartV2
        case .memoryAdjustment: .memoryAdjustmentV1
        case .settingsAdjustment: .settingsAdjustmentV1
        case .scheduleAdjustment: .scheduleAdjustmentV1
        case .reactiveDeload: .reactiveDeloadV1
        case .planRegenerate: .planRegenerateV1
        case .mealQuery: .mealQueryV1
        case .recoveryQuery: .recoveryQueryV1
        case .calendarQuery: .calendarQueryV1
        case .trendsQuery: .trendsQueryV1
        case .patternQuery: .patternQueryV1
        case .workoutQuery: .workoutQueryV1
        case .nutritionQuery: .nutritionQueryV1
        case .contextRefresh: .contextRefreshV1
        case .healthSync: .healthSyncV1
        case .chart: .chartV1
        case .navigate: .navigateV1
        case .workoutDiscard: .workoutDiscardV1
        }
    }

    /// Writes become confirm cards. Queries run immediately and feed a follow-up turn.
    public var isQuery: Bool {
        switch self {
        case .mealQuery, .recoveryQuery, .calendarQuery, .trendsQuery, .patternQuery, .workoutQuery, .nutritionQuery, .contextRefresh, .healthSync:
            true
        default:
            false
        }
    }

    public var isWrite: Bool {
        switch self {
        case .foodLog, .mealCopy, .workoutStart, .memoryAdjustment, .settingsAdjustment, .scheduleAdjustment, .reactiveDeload, .planRegenerate, .workoutDiscard:
            true
        default:
            false
        }
    }

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

    public static func pattern(from calls: [CoachLLMFunctionCall]) -> PatternQueryPayload? {
        decode(PatternQueryPayload.self, named: .patternQuery, from: calls)
    }

    public static func workout(from calls: [CoachLLMFunctionCall]) -> WorkoutQueryPayload? {
        decode(WorkoutQueryPayload.self, named: .workoutQuery, from: calls)
    }

    public static func nutrition(from calls: [CoachLLMFunctionCall]) -> NutritionQueryPayload? {
        decode(NutritionQueryPayload.self, named: .nutritionQuery, from: calls)
    }

    public static func contextRefresh(from calls: [CoachLLMFunctionCall]) -> ContextRefreshPayload? {
        decode(ContextRefreshPayload.self, named: .contextRefresh, from: calls)
    }

    public static func healthSync(from calls: [CoachLLMFunctionCall]) -> HealthSyncPayload? {
        decode(HealthSyncPayload.self, named: .healthSync, from: calls)
    }

    public static func chart(from calls: [CoachLLMFunctionCall]) -> ChartPayload? {
        decode(ChartPayload.self, named: .chart, from: calls)
    }

    public static func navigate(from calls: [CoachLLMFunctionCall]) -> NavigatePayload? {
        decode(NavigatePayload.self, named: .navigate, from: calls)
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

/// Resolves a catalog query from a tool call, with JSON and intent as fallback.
public enum CoachCatalogQueryResolver {
    public static func resolve<Payload>(
        named name: CoachCatalogToolName,
        functionCalls: [CoachLLMFunctionCall],
        assembledText: String,
        userText: String,
        decode: ([CoachLLMFunctionCall]) -> Payload?,
        parseJSON: (String) -> Payload?,
        infer: (String) -> Payload?
    ) -> Payload? {
        if CoachCatalogToolName.hasWrite(in: functionCalls) {
            return nil
        }
        if functionCalls.contains(where: { $0.name == name.rawValue }) {
            return decode(functionCalls) ?? parseJSON(assembledText) ?? infer(userText)
        }
        return parseJSON(assembledText) ?? infer(userText)
    }

    /// Query tool names actually invoked this turn. Empty means follow-ups may use JSON/intent.
    public static func explicitQueryNames(in calls: [CoachLLMFunctionCall]) -> Set<CoachCatalogToolName> {
        Set(calls.compactMap { CoachCatalogToolName(rawValue: $0.name) }.filter(\.isQuery))
    }

    /// At most one catalog follow-up per user turn. Prefer an explicit query tool over intent.
    public static func shouldFollowUp(
        _ name: CoachCatalogToolName,
        explicitQueries: Set<CoachCatalogToolName>
    ) -> Bool {
        explicitQueries.isEmpty || explicitQueries.contains(name)
    }

    /// Live wearable refresh always runs, even if the model called recovery_query instead.
    public static func shouldRunHealthSyncFollowUp(
        inferred: Bool,
        explicitQueries: Set<CoachCatalogToolName>
    ) -> Bool {
        inferred || shouldFollowUp(.healthSync, explicitQueries: explicitQueries)
    }

    /// Chart/navigate from the follow-up stream, else the original turn (tools then JSON).
    public static func mergeNonQueryPayload<Payload>(
        currentCalls: [CoachLLMFunctionCall],
        originalCalls: [CoachLLMFunctionCall],
        currentText: String,
        originalText: String,
        decode: ([CoachLLMFunctionCall]) -> Payload?,
        parseJSON: (String) -> Payload?
    ) -> Payload? {
        decode(currentCalls)
            ?? decode(originalCalls)
            ?? parseJSON(currentText)
            ?? parseJSON(originalText)
    }
}
