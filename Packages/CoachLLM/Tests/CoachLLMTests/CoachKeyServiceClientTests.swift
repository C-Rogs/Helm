import Foundation
import Testing
@testable import CoachLLM

@Suite("CoachKeyServiceClient", .serialized)
struct CoachKeyServiceClientTests {
    private func makeSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = handler
        return URLSession(configuration: config)
    }

    private let baseURL = URL(string: "https://coach-key.example/v1/provision")!
    private let deviceId = "550e8400-e29b-41d4-a716-446655440000"

    @Test("provision decodes a new capped key")
    func provisionNewKey() async throws {
        let client = CoachKeyServiceClient(
            session: makeSession { request in
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/v1/provision")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret")

                let response = HTTPURLResponse(
                    url: self.baseURL,
                    statusCode: 201,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let payload = """
                {
                  "key": "fixture-openrouter-key-new",
                  "provisioned": true,
                  "free_models_only": true,
                  "limit_usd": 0,
                  "limit_reset": "monthly"
                }
                """.data(using: .utf8)!
                return (response, payload)
            },
            baseURL: URL(string: "https://coach-key.example")!,
            appSharedSecret: "test-secret",
            isConfigured: true
        )

        let result = try await client.provision(deviceId: deviceId)
        #expect(result.key == "fixture-openrouter-key-new")
        #expect(result.provisioned)
        #expect(result.freeModelsOnly == true)
        #expect(result.limitUSD == 0)
        #expect(result.limitReset == "monthly")
    }

    @Test("provision returns existing key without error")
    func provisionExistingKey() async throws {
        let client = CoachKeyServiceClient(
            session: makeSession { _ in
                let response = HTTPURLResponse(
                    url: self.baseURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let payload = """
                {"key":"fixture-openrouter-key-existing","provisioned":false,"free_models_only":true}
                """.data(using: .utf8)!
                return (response, payload)
            },
            baseURL: URL(string: "https://coach-key.example")!,
            appSharedSecret: "test-secret",
            isConfigured: true
        )

        let result = try await client.provision(deviceId: deviceId)
        #expect(result.key == "fixture-openrouter-key-existing")
        #expect(!result.provisioned)
    }

    @Test("unconfigured client throws notConfigured")
    func notConfigured() async {
        let client = CoachKeyServiceClient(
            session: makeSession { _ in
                Issue.record("Should not hit network when unconfigured")
                fatalError()
            },
            baseURL: nil,
            appSharedSecret: "",
            isConfigured: false
        )

        await #expect(throws: CoachKeyServiceError.notConfigured) {
            _ = try await client.provision(deviceId: deviceId)
        }
    }

    @Test("401 maps to unauthorized")
    func unauthorized() async {
        let client = configuredClient(statusCode: 401, body: #"{"error":"unauthorized"}"#)
        await #expect(throws: CoachKeyServiceError.unauthorized) {
            _ = try await client.provision(deviceId: deviceId)
        }
    }

    @Test("device cap maps to deviceCapReached")
    func deviceCapReached() async {
        let client = configuredClient(statusCode: 503, body: #"{"error":"device_cap_reached"}"#)
        await #expect(throws: CoachKeyServiceError.deviceCapReached) {
            _ = try await client.provision(deviceId: deviceId)
        }
    }

    @Test("empty key in success response is invalid")
    func emptyKeyRejected() async {
        let client = configuredClient(statusCode: 200, body: #"{"key":"   ","provisioned":true}"#)
        await #expect(throws: CoachKeyServiceError.invalidResponse) {
            _ = try await client.provision(deviceId: deviceId)
        }
    }

    private func configuredClient(statusCode: Int, body: String) -> CoachKeyServiceClient {
        CoachKeyServiceClient(
            session: makeSession { _ in
                let response = HTTPURLResponse(
                    url: self.baseURL,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data(body.utf8))
            },
            baseURL: URL(string: "https://coach-key.example")!,
            appSharedSecret: "test-secret",
            isConfigured: true
        )
    }
}

@Suite("HelmDeviceIdentity")
struct HelmDeviceIdentityTests {
    @Test("device id is stable across reads")
    func stableDeviceId() throws {
        let first = try HelmDeviceIdentity.deviceId()
        let second = try HelmDeviceIdentity.deviceId()
        #expect(first == second)
        #expect(first.contains("-"))
    }
}

@Suite("OpenRouterKeyProvisioner")
struct OpenRouterKeyProvisionerTests {
    @Test("skips when openrouter key already present")
    func skipsWhenPresent() async {
        let store = APIKeyStore(service: "com.cameronro.helm.tests.\(UUID().uuidString)")
        try? store.save("existing-key", kind: .openRouter)

        let result = await OpenRouterKeyProvisioner.provisionIfNeeded(
            keyStore: store,
            client: CoachKeyServiceClient(
                session: .shared,
                baseURL: URL(string: "https://example.com")!,
                appSharedSecret: "secret",
                isConfigured: true
            )
        )

        #if DEBUG
        #expect(result == .skippedDebugBuild)
        #else
        #expect(result == .alreadyPresent)
        #endif
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
