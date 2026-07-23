public enum APIKeyKind: String, Sendable, CaseIterable {
    case gemini
    case openRouter

    public var secretsFileName: String {
        switch self {
        case .gemini:
            "gemini.key"
        case .openRouter:
            "openrouter.key"
        }
    }
}
