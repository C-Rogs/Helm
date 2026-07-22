public enum APIKeyKind: String, Sendable, CaseIterable {
    case gemini

    public var secretsFileName: String {
        "\(rawValue).key"
    }
}
