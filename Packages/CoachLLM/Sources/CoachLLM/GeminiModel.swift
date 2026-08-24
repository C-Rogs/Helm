/// Gemini model route for the AI Studio REST API.
///
/// Google enforces RPM/RPD per model ID, not per key. Helm pins explicit
/// models so coach traffic lands on the free-tier bucket with headroom.
public enum GeminiModel: String, Sendable, Equatable {
    case flashLite = "gemini-3.5-flash-lite"
    /// Retired for new AI Studio keys (404). Kept for tests / explicit overrides only.
    case flash = "gemini-2.5-flash"
    case flashLite31 = "gemini-3.1-flash-lite"
    case flash35 = "gemini-3.5-flash"
}

extension GeminiModel {
    public static let `default` = GeminiModel.flashLite
    /// Low-complexity classification (calendar event titles, etc).
    public static let calendar = GeminiModel.flashLite31
    /// Primary meal vision model.
    public static let mealVision = GeminiModel.flash35

    public static let mealVisionCandidates: [GeminiModel] = [.flash35, .flashLite]
}
