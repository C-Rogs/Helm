import Foundation
import Testing
@testable import CoachLLM

@Suite("Coach user-facing errors")
struct CoachUserFacingErrorTests {
    @Test("HTTP 429 maps to rate-limited coach message")
    func http429RateLimit() {
        let error = CoachProviderError.fromHTTPStatusCode(429)
        #expect(error == .rateLimited)
        #expect(
            CoachUserFacingError.message(for: error)
                == "Coach is cooling down. Try again shortly."
        )
        let degraded = CoachFailurePolicy.degradedState(for: error)
        #expect(degraded.reason == .rateLimited)
        #expect(degraded.userMessage == "Coach is cooling down. Numbers and logging still work.")
    }

    @Test("structured output errors have readable messages")
    func structuredOutputMessages() {
        #expect(
            CoachUserFacingError.message(for: CoachStructuredOutputError.decodingFailed("detail"))
                == "Coach returned an invalid adjustment. Try rephrasing."
        )
        #expect(
            CoachUserFacingError.message(for: CoachProviderError.timeout)
                == "Coach timed out. Check your connection and try again."
        )
    }

    @Test("JSON sanitizer strips markdown fences")
    func jsonSanitizer() {
        let wrapped = """
        ```json
        {"schemaVersion":"session_adjustment.v1"}
        ```
        """
        #expect(
            CoachJSONSanitizer.sanitize(wrapped) == "{\"schemaVersion\":\"session_adjustment.v1\"}"
        )
    }
}
