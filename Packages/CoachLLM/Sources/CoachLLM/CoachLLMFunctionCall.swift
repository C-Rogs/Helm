import Foundation

/// One catalog tool call from a chat stream. Provider-neutral; adapters fill `name` + JSON args.
public struct CoachLLMFunctionCall: Sendable, Equatable {
    public let name: String
    public let argumentsJSON: Data

    public init(name: String, argumentsJSON: Data) {
        self.name = name
        self.argumentsJSON = argumentsJSON
    }

    public init(name: String, arguments: [String: Any]) {
        self.name = name
        if JSONSerialization.isValidJSONObject(arguments),
           let data = try? JSONSerialization.data(withJSONObject: arguments) {
            argumentsJSON = data
        } else {
            argumentsJSON = Data("{}".utf8)
        }
    }

    /// Decodes tool args into an existing Coach payload, injecting `schemaVersion` when omitted.
    public func decode<Payload: Decodable>(
        _ type: Payload.Type,
        schemaVersion: CoachOutputSchemaVersion
    ) throws -> Payload {
        let object = try JSONSerialization.jsonObject(with: argumentsJSON)
        guard var dict = object as? [String: Any] else {
            throw CoachStructuredOutputError.decodingFailed("function call args are not an object")
        }
        if dict["schemaVersion"] == nil {
            dict["schemaVersion"] = schemaVersion.rawValue
        }
        guard JSONSerialization.isValidJSONObject(dict) else {
            throw CoachStructuredOutputError.decodingFailed("function call args are not valid JSON")
        }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(Payload.self, from: data)
    }
}

public enum CoachLLMStreamEvent: Sendable {
    case text(String)
    case functionCall(CoachLLMFunctionCall)

    /// Providers without native tools wrap a text stream as a catalog turn.
    public static func wrapping(
        _ stream: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<CoachLLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in stream {
                        continuation.yield(.text(chunk))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
