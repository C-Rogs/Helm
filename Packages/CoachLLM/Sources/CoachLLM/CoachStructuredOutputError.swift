public enum CoachStructuredOutputError: Error, Sendable, Equatable {
    case schemaVersionMismatch(expected: String, found: String)
    case decodingFailed(String)
    case emptyResponse
}
