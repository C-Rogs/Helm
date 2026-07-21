public enum HelmError: Error, Sendable, Equatable {
    case invalidInput(String)
    case missingRequiredData(String)
    case outOfRange(String)
}
