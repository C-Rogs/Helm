import Foundation

/// Provider-neutral catalog write tools. Each LLM adapter maps these names
/// into its native tool format (Gemini functionDeclarations, OpenRouter tools, etc).
public enum CoachCatalogToolName: String, Sendable, CaseIterable {
    case foodLog = "food_log"
    case mealCopy = "meal_copy"
    case workoutStart = "workout_start"
    case memoryAdjustment = "memory_adjustment"
    case settingsAdjustment = "settings_adjustment"
    case reactiveDeload = "reactive_deload"
    case planRegenerate = "plan_regenerate"

    public var schemaVersion: CoachOutputSchemaVersion {
        switch self {
        case .foodLog: .foodLogV1
        case .mealCopy: .mealCopyV1
        case .workoutStart: .workoutStartV2
        case .memoryAdjustment: .memoryAdjustmentV1
        case .settingsAdjustment: .settingsAdjustmentV1
        case .reactiveDeload: .reactiveDeloadV1
        case .planRegenerate: .planRegenerateV1
        }
    }
}
