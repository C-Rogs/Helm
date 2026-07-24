import Foundation

public struct OpenRouterHTTPRequest: Sendable {
    public let requestID: UUID
    public let apiKey: String
    public let body: Data

    public init(requestID: UUID, apiKey: String, body: Data) {
        self.requestID = requestID
        self.apiKey = apiKey
        self.body = body
    }
}

public protocol OpenRouterHTTPClient: Sendable {
    func chatCompletion(_ request: OpenRouterHTTPRequest) async throws -> Data
}

public final class LiveOpenRouterHTTPClient: OpenRouterHTTPClient, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func chatCompletion(_ request: OpenRouterHTTPRequest) async throws -> Data {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw CoachProviderError.requestFailed("Invalid OpenRouter endpoint.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(request.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("Helm", forHTTPHeaderField: "HTTP-Referer")
        urlRequest.setValue("Helm iOS", forHTTPHeaderField: "X-Title")
        urlRequest.httpBody = request.body

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw CoachProviderError.requestFailed("OpenRouter returned an invalid response.")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            let bodySnippet = Self.errorSnippet(from: data)
            if bodySnippet.isEmpty {
                throw CoachProviderError.requestFailed("OpenRouter request failed with status \(http.statusCode).")
            }
            throw CoachProviderError.requestFailed(
                "OpenRouter request failed with status \(http.statusCode): \(bodySnippet)"
            )
        }
        return data
    }

    private static func errorSnippet(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return String(text.prefix(240))
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return String(message.prefix(240))
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return String(message.prefix(240))
        }
        return ""
    }
}

public final class FixtureOpenRouterHTTPClient: OpenRouterHTTPClient, @unchecked Sendable {
    private let bundle: Bundle

    public init(bundle: Bundle) {
        self.bundle = bundle
    }

    public func chatCompletion(_ request: OpenRouterHTTPRequest) async throws -> Data {
        guard let url = bundle.url(forResource: "openrouter_meal_decomposition", withExtension: "json") else {
            throw CoachProviderError.requestFailed("Missing openrouter_meal_decomposition.json fixture")
        }
        return try Data(contentsOf: url)
    }
}
