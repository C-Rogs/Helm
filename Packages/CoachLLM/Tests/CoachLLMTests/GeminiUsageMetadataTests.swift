import Foundation
import Testing
@testable import CoachLLM

@Suite("Gemini usage metadata")
struct GeminiUsageMetadataTests {
    @Test("parses cachedContentTokenCount from generateContent payload")
    func parsesCachedTokens() throws {
        let json = """
        {
          "candidates": [{"content": {"parts": [{"text": "hi"}]}}],
          "usageMetadata": {
            "promptTokenCount": 1200,
            "cachedContentTokenCount": 800,
            "candidatesTokenCount": 40,
            "totalTokenCount": 1240
          }
        }
        """
        let data = try #require(json.data(using: .utf8))
        let usage = try #require(GeminiSSEParser.usageMetadata(fromResponseData: data))
        #expect(usage.promptTokenCount == 1200)
        #expect(usage.cachedContentTokenCount == 800)
        #expect(usage.candidatesTokenCount == 40)
        #expect(usage.summary.contains("cached=800"))
    }

    @Test("missing usageMetadata returns nil")
    func missingUsageReturnsNil() throws {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"hi"}]}}]}"#
        let data = try #require(json.data(using: .utf8))
        #expect(GeminiSSEParser.usageMetadata(fromResponseData: data) == nil)
    }
}
