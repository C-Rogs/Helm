import Foundation
import OSLog

private let coachLLMStreamLog = Logger(subsystem: "com.cameronro.helm", category: "CoachLLM")

public struct GeminiStreamHTTPRequest: Sendable {
    public let requestID: UUID
    public let model: GeminiModel
    public let apiKey: String
    public let body: Data

    public init(requestID: UUID, model: GeminiModel, apiKey: String, body: Data) {
        self.requestID = requestID
        self.model = model
        self.apiKey = apiKey
        self.body = body
    }
}

public struct GeminiGenerateHTTPRequest: Sendable {
    public let requestID: UUID
    public let model: GeminiModel
    public let apiKey: String
    public let body: Data

    public init(requestID: UUID, model: GeminiModel, apiKey: String, body: Data) {
        self.requestID = requestID
        self.model = model
        self.apiKey = apiKey
        self.body = body
    }
}

public protocol GeminiHTTPClient: Sendable {
    var lastStreamRequestID: UUID? { get }
    var lastGenerateRequestID: UUID? { get }

    func streamGenerate(_ request: GeminiStreamHTTPRequest) async throws -> AsyncThrowingStream<Data, Error>
    func generateContent(_ request: GeminiGenerateHTTPRequest) async throws -> Data
}

public enum GeminiStreamAssembler {
    public static func textChunks(from stream: AsyncThrowingStream<Data, Error>) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var lastUsage: GeminiUsageMetadata?
                do {
                    for try await chunk in stream {
                        for line in GeminiSSEParser.eventDataLines(from: chunk) {
                            if let streamError = GeminiSSEParser.streamErrorMessage(from: line) {
                                throw CoachProviderError.requestFailed(
                                    "Gemini stream error: \(streamError)"
                                )
                            }
                            if let usage = GeminiSSEParser.usageMetadata(fromJSONString: line) {
                                lastUsage = usage
                            }
                            if let text = GeminiSSEParser.textDelta(from: line), !text.isEmpty {
                                continuation.yield(text)
                            }
                        }
                    }
                    if let lastUsage {
                        coachLLMStreamLog.debug(
                            "Gemini stream usage \(lastUsage.summary, privacy: .public)"
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public static func reassembleText(from stream: AsyncThrowingStream<Data, Error>) async throws -> String {
        let textStream = textChunks(from: stream)
        return try await FixtureStreamHarness.reassemble(textStream)
    }
}

public final class LiveGeminiHTTPClient: GeminiHTTPClient, @unchecked Sendable {
    private let session: URLSession
    private let streamRequestIDLock = NSLock()
    private let generateRequestIDLock = NSLock()
    private nonisolated(unsafe) var _lastStreamRequestID: UUID?
    private nonisolated(unsafe) var _lastGenerateRequestID: UUID?

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public var lastStreamRequestID: UUID? {
        streamRequestIDLock.withLock { _lastStreamRequestID }
    }

    public var lastGenerateRequestID: UUID? {
        generateRequestIDLock.withLock { _lastGenerateRequestID }
    }

    public func streamGenerate(_ request: GeminiStreamHTTPRequest) async throws -> AsyncThrowingStream<Data, Error> {
        streamRequestIDLock.withLock { _lastStreamRequestID = request.requestID }
        let url = GeminiEndpoint.streamGenerateURL(model: request.model, apiKey: request.apiKey)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = request.body
        let preparedRequest = urlRequest

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await session.bytes(for: preparedRequest)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: CoachProviderError.requestFailed("Invalid response"))
                        return
                    }
                    guard (200 ..< 300).contains(http.statusCode) else {
                        let errorData = try await Self.collectErrorBody(from: bytes)
                        let providerError = Self.providerError(statusCode: http.statusCode, data: errorData)
                        coachLLMStreamLog.error(
                            "Gemini stream HTTP \(http.statusCode, privacy: .public) requestID=\(request.requestID.uuidString, privacy: .public)"
                        )
                        continuation.finish(throwing: providerError)
                        return
                    }
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == 0x0A {
                            let chunk = buffer
                            buffer = Data()
                            continuation.yield(chunk)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch {
                    coachLLMStreamLog.error(
                        "Gemini stream transport failure requestID=\(request.requestID.uuidString, privacy: .public) \(String(describing: type(of: error)), privacy: .public)"
                    )
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func generateContent(_ request: GeminiGenerateHTTPRequest) async throws -> Data {
        generateRequestIDLock.withLock { _lastGenerateRequestID = request.requestID }
        let url = GeminiEndpoint.generateContentURL(model: request.model, apiKey: request.apiKey)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = request.body

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw CoachProviderError.requestFailed("Invalid response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            coachLLMStreamLog.error(
                "Gemini generate HTTP \(http.statusCode, privacy: .public) requestID=\(request.requestID.uuidString, privacy: .public)"
            )
            throw Self.providerError(statusCode: http.statusCode, data: data)
        }
        return data
    }

    private static func providerError(statusCode: Int, data: Data) -> CoachProviderError {
        switch statusCode {
        case 429:
            return .rateLimited
        case 408, 504:
            return .timeout
        default:
            return .requestFailed(errorDetail(statusCode: statusCode, data: data))
        }
    }

    private static func collectErrorBody(
        from bytes: URLSession.AsyncBytes,
        limit: Int = 4_096
    ) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(limit, 1_024))
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return data
    }

    private static func errorDetail(statusCode: Int, data: Data) -> String {
        let bodySnippet = errorSnippet(from: data)
        if statusCode == 401 || statusCode == 403 {
            if bodySnippet.isEmpty {
                return "Gemini rejected the API key (HTTP \(statusCode)). Check Settings → Coach."
            }
            return "Gemini rejected the API key (HTTP \(statusCode)): \(bodySnippet)"
        }
        if bodySnippet.isEmpty {
            return "Gemini request failed with status \(statusCode)."
        }
        return "Gemini request failed with status \(statusCode): \(bodySnippet)"
    }

    private static func errorSnippet(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return String(text.prefix(240))
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return String(message.prefix(240))
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return String(message.prefix(240))
        }
        return ""
    }
}

public final class FixtureGeminiHTTPClient: GeminiHTTPClient, @unchecked Sendable {
    private let bundle: Bundle
    private let lock = NSLock()
    private var _lastStreamRequestID: UUID?
    private var _lastGenerateRequestID: UUID?

    public init(bundle: Bundle) {
        self.bundle = bundle
    }

    public var lastStreamRequestID: UUID? {
        lock.withLock { _lastStreamRequestID }
    }

    public var lastGenerateRequestID: UUID? {
        lock.withLock { _lastGenerateRequestID }
    }

    public func streamGenerate(_ request: GeminiStreamHTTPRequest) async throws -> AsyncThrowingStream<Data, Error> {
        lock.withLock { _lastStreamRequestID = request.requestID }
        guard let url = bundle.url(forResource: "gemini_stream_sse", withExtension: "json") else {
            throw CoachProviderError.requestFailed("Missing gemini_stream_sse.json fixture")
        }
        let data = try Data(contentsOf: url)
        let lines = try JSONDecoder().decode([String].self, from: data)
        return AsyncThrowingStream { continuation in
            Task {
                for line in lines {
                    continuation.yield(Data(line.utf8))
                }
                continuation.finish()
            }
        }
    }

    public func generateContent(_ request: GeminiGenerateHTTPRequest) async throws -> Data {
        lock.withLock { _lastGenerateRequestID = request.requestID }
        let fixtureName: String
        if requestIncludesMealPhoto(request.body) {
            fixtureName = requestIncludesMealDecomposition(request.body)
                ? "gemini_generate_meal_decomposition"
                : "gemini_generate_meal_estimate"
        } else {
            fixtureName = "gemini_generate_session_adjustment"
        }
        guard let url = bundle.url(forResource: fixtureName, withExtension: "json") else {
            throw CoachProviderError.requestFailed("Missing \(fixtureName).json fixture")
        }
        return try Data(contentsOf: url)
    }

    private func requestIncludesMealPhoto(_ body: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let contents = object["contents"] as? [[String: Any]]
        else {
            return false
        }

        for content in contents {
            guard let parts = content["parts"] as? [[String: Any]] else { continue }
            for part in parts {
                if part["inline_data"] != nil {
                    return true
                }
            }
        }
        return false
    }

    private func requestIncludesMealDecomposition(_ body: Data) -> Bool {
        guard let text = String(data: body, encoding: .utf8) else { return false }
        return text.contains(CoachOutputSchemaVersion.mealDecompositionV1.rawValue)
    }
}
