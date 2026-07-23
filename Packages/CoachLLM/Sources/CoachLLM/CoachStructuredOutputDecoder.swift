import Foundation

public enum CoachJSONSanitizer: Sendable {
    public static func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}") {
            return String(text[start ... end])
        }
        return text
    }
}

public enum CoachStructuredOutputDecoder: Sendable {
    private struct SchemaProbe: Decodable {
        let schemaVersion: String
    }

    public static func decode<Payload: Decodable>(
        _ type: Payload.Type,
        from jsonText: String,
        expectedSchema: CoachOutputSchemaVersion
    ) throws -> Payload {
        let sanitized = CoachJSONSanitizer.sanitize(jsonText)
        let data = Data(sanitized.utf8)
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
