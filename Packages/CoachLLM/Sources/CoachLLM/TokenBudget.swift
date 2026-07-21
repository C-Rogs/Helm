/// Per-backend input token caps and the chars-per-token estimator shared with the context builder.
public enum TokenBudget: Sendable {
    public static let charsPerToken = 3.5

    public static func maxInputTokens(for kind: ProviderKind) -> Int {
        switch kind {
        case .gemini:
            48_000
        case .foundationModels:
            4_096
        case .openRouter:
            32_000
        }
    }

    public static func estimateTokens(characterCount: Int) -> Int {
        guard characterCount > 0 else { return 0 }
        return max(1, Int((Double(characterCount) / charsPerToken).rounded(.up)))
    }

    public static func characterBudget(for kind: ProviderKind, reservedTokens: Int) -> Int {
        let available = max(0, maxInputTokens(for: kind) - reservedTokens)
        return Int(Double(available) * charsPerToken)
    }
}
