public enum APIKeyKind: String, Sendable, CaseIterable {
    case gemini
    case openRouter
    case spotifyClientID
    case linear

    public var secretsFileName: String {
        switch self {
        case .gemini:
            "gemini.key"
        case .openRouter:
            "openrouter.key"
        case .spotifyClientID:
            "spotify-client-id.key"
        case .linear:
            "linear.key"
        }
    }
}
