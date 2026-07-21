/// Backends the registry can vend. Exhaustive over Helm's provider slots.
public enum ProviderKind: String, Sendable, CaseIterable, Equatable {
    case gemini
    case foundationModels
    case openRouter
}
