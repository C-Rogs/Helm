import Foundation

public enum CoachChatTextFormatter: Sendable {
    private static let structuredSchemas = Set(
        CoachOutputSchemaVersion.allCases.map(\.rawValue)
    )

    public static func userFacingText(from text: String) -> String {
        var result = text
        for block in CoachEmbeddedJSONBlockFinder.blocks(in: text) {
            let sanitized = CoachJSONSanitizer.sanitize(block)
            guard let data = sanitized.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let schemaVersion = object["schemaVersion"] as? String,
                  structuredSchemas.contains(schemaVersion)
            else {
                continue
            }
            result = result.replacingOccurrences(of: block, with: "")
        }

        result = result
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")

        return result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }
}
