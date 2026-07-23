import Foundation

enum GeminiEndpoint {
    static let host = "generativelanguage.googleapis.com"
    static let apiPrefix = "/v1beta"

    static func streamGenerateURL(model: GeminiModel, apiKey: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "\(apiPrefix)/models/\(model.rawValue):streamGenerateContent"
        components.queryItems = [
            URLQueryItem(name: "alt", value: "sse"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components.url else {
            preconditionFailure("Invalid Gemini stream URL components")
        }
        return url
    }

    static func generateContentURL(model: GeminiModel, apiKey: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "\(apiPrefix)/models/\(model.rawValue):generateContent"
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            preconditionFailure("Invalid Gemini generate URL components")
        }
        return url
    }
}
