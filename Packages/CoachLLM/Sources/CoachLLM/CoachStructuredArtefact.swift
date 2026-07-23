public struct CoachStructuredArtefact<Payload: Sendable>: Sendable, Equatable where Payload: Equatable {
    public let payload: Payload
    public let schemaVersion: CoachOutputSchemaVersion
    public let promptVersion: CoachPromptVersion

    public init(
        payload: Payload,
        schemaVersion: CoachOutputSchemaVersion,
        promptVersion: CoachPromptVersion
    ) {
        self.payload = payload
        self.schemaVersion = schemaVersion
        self.promptVersion = promptVersion
    }
}
