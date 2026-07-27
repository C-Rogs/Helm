import Foundation

public struct CoachStructuredArtefact<Payload: Sendable>: Sendable, Equatable where Payload: Equatable {
    public let payload: Payload
    public let schemaVersion: CoachOutputSchemaVersion
    public let promptVersion: CoachPromptVersion
    public let requestID: UUID?

    public init(
        payload: Payload,
        schemaVersion: CoachOutputSchemaVersion,
        promptVersion: CoachPromptVersion,
        requestID: UUID? = nil
    ) {
        self.payload = payload
        self.schemaVersion = schemaVersion
        self.promptVersion = promptVersion
        self.requestID = requestID
    }
}
