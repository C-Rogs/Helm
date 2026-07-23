/// Gemini model route for the AI Studio REST API.
///
/// Google enforces RPM/RPD per model ID, not per key. Helm pins an explicit
/// model so coach traffic lands on the free-tier bucket with headroom (3.5 Flash-Lite).
public enum GeminiModel: String, Sendable, Equatable {
    case flashLite = "gemini-3.5-flash-lite"
}

extension GeminiModel {
    public static let `default` = GeminiModel.flashLite
}
