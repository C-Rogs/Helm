import Foundation

public struct CoachKeyProvisionResponse: Decodable, Sendable, Equatable {
    public let key: String
    public let provisioned: Bool
    public let freeModelsOnly: Bool?
    public let limitUSD: Double?
    public let limitReset: String?

    enum CodingKeys: String, CodingKey {
        case key
        case provisioned
        case freeModelsOnly = "free_models_only"
        case limitUSD = "limit_usd"
        case limitReset = "limit_reset"
    }
}

public enum CoachKeyServiceError: Error, Sendable, Equatable {
    case notConfigured
    case invalidResponse
    case unauthorized
    case deviceCapReached
    case serverError(String)
}

public struct CoachKeyServiceClient: Sendable {
    private let session: URLSession
    private let baseURL: URL?
    private let appSharedSecret: String
    private let isConfigured: Bool

    public init(session: URLSession = .shared) {
        self.init(
            session: session,
            baseURL: CoachKeyServiceConfig.baseURL,
            appSharedSecret: CoachKeyServiceConfig.appSharedSecret,
            isConfigured: CoachKeyServiceConfig.isConfigured
        )
    }

    init(
        session: URLSession,
        baseURL: URL?,
        appSharedSecret: String,
        isConfigured: Bool
    ) {
        self.session = session
        self.baseURL = baseURL
        self.appSharedSecret = appSharedSecret
        self.isConfigured = isConfigured
    }

    public func provision(deviceId: String) async throws -> CoachKeyProvisionResponse {
        guard isConfigured, let baseURL else {
            throw CoachKeyServiceError.notConfigured
        }

        var request = URLRequest(url: baseURL.appending(path: "v1/provision"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(appSharedSecret)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONEncoder().encode(["device_id": deviceId])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoachKeyServiceError.invalidResponse
        }

        if http.statusCode == 401 {
            throw CoachKeyServiceError.unauthorized
        }

        if http.statusCode == 503,
           let payload = try? JSONDecoder().decode(ServerErrorBody.self, from: data),
           payload.error == "device_cap_reached"
        {
            throw CoachKeyServiceError.deviceCapReached
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let payload = try? JSONDecoder().decode(ServerErrorBody.self, from: data)
            throw CoachKeyServiceError.serverError(
                payload?.detail ?? payload?.error ?? "HTTP \(http.statusCode)"
            )
        }

        let decoded = try JSONDecoder().decode(CoachKeyProvisionResponse.self, from: data)
        guard !decoded.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CoachKeyServiceError.invalidResponse
        }
        return decoded
    }

    private struct ServerErrorBody: Decodable {
        let error: String?
        let detail: String?
    }
}
