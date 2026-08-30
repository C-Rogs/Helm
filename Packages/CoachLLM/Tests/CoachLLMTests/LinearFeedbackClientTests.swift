import Foundation
import Testing
@testable import CoachLLM

@Suite("LinearFeedbackClient", .serialized)
struct LinearFeedbackClientTests {
    private func makeSession(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LinearStubURLProtocol.self]
        LinearStubURLProtocol.handler = handler
        return URLSession(configuration: config)
    }

    @Test("submit posts bug payload with name and transcript")
    func submitIncludesTranscript() async throws {
        let store = APIKeyStore(service: "com.cameronro.helm.tests.linear.\(UUID().uuidString)")
        try store.save("lin_api_testkey", kind: .linear)

        let client = LinearFeedbackClient(
            session: makeSession { request in
                #expect(request.httpMethod == "POST")
                #expect(request.url?.host == "api.linear.app")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "lin_api_testkey")
                let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
                #expect(body.contains("Rest timer skipped a set"))
                #expect(body.contains("From: Alex"))
                #expect(body.contains("**You:** hello"))
                #expect(body.contains(LinearFeedbackConfig.bugLabelID))
                #expect(body.contains(LinearFeedbackConfig.testFlightLabelID))
                let response = HTTPURLResponse(
                    url: LinearFeedbackConfig.graphQLURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                let payload = """
                {"data":{"issueCreate":{"success":true,"issue":{"url":"https://linear.app/camlab/issue/CAM-99"}}}}
                """.data(using: .utf8)!
                return (response, payload)
            },
            apiKeyStore: store
        )

        let url = try await client.submit(
            LinearFeedbackDraft(
                kind: .bug,
                title: "Rest timer skipped a set",
                details: "Timer jumped from 90s to done after I logged the set.",
                fromName: "Alex",
                coachHistoryMarkdown: "**You:** hello"
            )
        )
        #expect(url?.absoluteString == "https://linear.app/camlab/issue/CAM-99")
    }

    @Test("rejects a missing title")
    func rejectsShortTitle() async {
        let store = APIKeyStore(service: "com.cameronro.helm.tests.linear.\(UUID().uuidString)")
        try? store.save("lin_api_testkey", kind: .linear)
        let client = LinearFeedbackClient(session: makeSession { _ in
            throw URLError(.badServerResponse)
        }, apiKeyStore: store)
        await #expect(throws: LinearFeedbackError.invalidInput("Give it a short title.")) {
            try await client.submit(
                LinearFeedbackDraft(kind: .bug, title: "Hi", details: "Need more detail here.", fromName: "Alex")
            )
        }
    }
}

private final class LinearStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

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
