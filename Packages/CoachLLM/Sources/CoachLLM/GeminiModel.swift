/// Gemini model route for the AI Studio REST API.
///
/// Google enforces RPM/RPD per model ID, not per key. Helm pins an explicit
/// model so coach traffic lands on the free-tier bucket with headroom (3.5 Flash-Lite).
public enum GeminiModel: String, Sendable, Equatable {
    case flashLite = "gemini-3.5-flash-lite"
    case flash = "gemini-2.5-flash"
}

extension GeminiModel {
    public static let `default` = GeminiModel.flashLite
    /// Same family as coach chat; `gemini-2.5-flash` often 404s on newer API keys.
    public static let mealVision = GeminiModel.flash

    public static let mealVisionCandidates: [GeminiModel] = [.flash, .flashLite]
}
