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

    static func functionCallDeltas(from eventJSON: String) -> [CoachLLMFunctionCall] {
        guard let data = eventJSON.data(using: .utf8) else { return [] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        guard let candidates = object["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else {
            return []
        }
        return parts.compactMap { part in
            guard let functionCall = part["functionCall"] as? [String: Any],
                  let name = functionCall["name"] as? String,
                  !name.isEmpty
            else {
                return nil
            }
            return CoachLLMFunctionCall(
                name: name,
                argumentsJSON: argumentsJSON(from: functionCall["args"])
            )
        }
    }

    static func argumentsJSON(from args: Any?) -> Data {
        if let dict = args as? [String: Any],
           JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict) {
            return data
        }
        if let string = args as? String, let data = string.data(using: .utf8) {
            return data
        }
        return Data("{}".utf8)
    }

    /// Gemini sometimes returns an error object as an SSE `data:` event instead of HTTP failure.
    static func streamErrorMessage(from eventJSON: String) -> String? {
        guard let data = eventJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else {
            return nil
        }
        if let message = error["message"] as? String, !message.isEmpty {
            return String(message.prefix(240))
        }
        if let status = error["status"] as? String, !status.isEmpty {
            return status
        }
        return "Gemini stream returned an error event."
    }

    /// Best-effort parse of Gemini `usageMetadata` (prompt / cached / output tokens).
    static func usageMetadata(from jsonObject: [String: Any]) -> GeminiUsageMetadata? {
        guard let usage = jsonObject["usageMetadata"] as? [String: Any] else { return nil }
        return GeminiUsageMetadata(
            promptTokenCount: intValue(usage["promptTokenCount"]),
            cachedContentTokenCount: intValue(usage["cachedContentTokenCount"]),
            candidatesTokenCount: intValue(usage["candidatesTokenCount"]),
            totalTokenCount: intValue(usage["totalTokenCount"])
        )
    }

    static func usageMetadata(fromJSONString json: String) -> GeminiUsageMetadata? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return usageMetadata(from: object)
    }

    static func usageMetadata(fromResponseData data: Data) -> GeminiUsageMetadata? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return usageMetadata(from: object)
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

    private static func intValue(_ any: Any?) -> Int? {
        if let int = any as? Int { return int }
        if let number = any as? NSNumber { return number.intValue }
        return nil
    }
}

struct GeminiUsageMetadata: Sendable, Equatable {
    let promptTokenCount: Int?
    let cachedContentTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?

    var summary: String {
        let prompt = promptTokenCount.map(String.init) ?? "?"
        let cached = cachedContentTokenCount.map(String.init) ?? "0"
        let out = candidatesTokenCount.map(String.init) ?? "?"
        let total = totalTokenCount.map(String.init) ?? "?"
        return "prompt=\(prompt) cached=\(cached) candidates=\(out) total=\(total)"
    }
}
