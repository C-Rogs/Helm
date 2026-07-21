public enum ProviderAvailability: Sendable, Equatable {
    case available
    case unavailable(label: String, helpText: String?)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}
