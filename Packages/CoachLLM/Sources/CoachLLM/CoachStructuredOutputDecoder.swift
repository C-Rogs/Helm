import Foundation

public enum CoachStructuredOutputDecoder: Sendable {
    private struct SchemaProbe: Decodable {
        let schemaVersion: String
    }

    public static func decode<Payload: Decodable>(
        _ type: Payload.Type,
        from jsonText: String,
        expectedSchema: CoachOutputSchemaVersion
    ) throws -> Payload {
        let data = Data(jsonText.utf8)
        let probe = try JSONDecoder().decode(SchemaProbe.self, from: data)
        guard probe.schemaVersion == expectedSchema.rawValue else {
            throw CoachStructuredOutputError.schemaVersionMismatch(
                expected: expectedSchema.rawValue,
                found: probe.schemaVersion
            )
        }
        do {
            return try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw CoachStructuredOutputError.decodingFailed(String(describing: error))
        }
    }
}
