import Foundation

enum GeminiSSEParser {
    static func eventDataLines(from chunk: Data) -> [String] {
        guard let text = String(data: chunk, encoding: .utf8) else { return [] }
        return text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("data:") }
            .map { String($0.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "[DONE]" }
    }

    static func textDelta(from eventJSON: String) -> String? {
        guard let data = eventJSON.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let candidates = object["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            return nil
        }
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    static func responseText(from responseData: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let candidates = object["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            throw CoachStructuredOutputError.emptyResponse
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw CoachStructuredOutputError.emptyResponse }
        return text
    }
}
