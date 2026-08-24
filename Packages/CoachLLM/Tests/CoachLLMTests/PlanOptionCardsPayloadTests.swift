import Foundation
import Testing
@testable import CoachLLM

@Suite("PlanOptionCardsPayload")
struct PlanOptionCardsPayloadTests {
    @Test("decodes plan_option_cards.v1 payload")
    func decodesPayload() throws {
        let json = """
        {
          "schemaVersion": "plan_option_cards.v1",
          "cards": [
            {
              "candidateID": "ppl_3day",
              "outcome": "Steady growth on three focused sessions.",
              "benefits": ["Classic split", "Easy scheduling"],
              "challenges": ["Each muscle hit weekly only"],
              "sources": ["Volume landmarks review"]
            },
            {
              "candidateID": "fullbody_3day",
              "outcome": "Higher frequency per muscle.",
              "benefits": ["Muscles stimulated 3x weekly"]
            }
          ]
        }
        """
        let payload = try JSONDecoder().decode(PlanOptionCardsPayload.self, from: Data(json.utf8))
        #expect(payload.schemaVersion == CoachOutputSchemaVersion.planOptionCardsV1.rawValue)
        #expect(payload.cards.count == 2)
        #expect(payload.cards[0].candidateID == "ppl_3day")
        #expect(payload.cards[0].benefits.count == 2)
        #expect(payload.cards[0].sources == ["Volume landmarks review"])
        // Optional fields default when absent.
        #expect(payload.cards[1].challenges.isEmpty)
        #expect(payload.cards[1].sources.isEmpty)
    }

    @Test("schema version mismatch rejected by structured decoder")
    func rejectsWrongSchema() {
        let json = #"{"schemaVersion":"plan_option_cards.v9","cards":[]}"#
        do {
            _ = try CoachStructuredOutputDecoder.decode(
                PlanOptionCardsPayload.self,
                from: json,
                expectedSchema: .planOptionCardsV1
            )
            Issue.record("Expected schema mismatch to throw")
        } catch {
            // Expected path.
        }
    }

    @Test("structured decoder accepts matching schema")
    func acceptsMatchingSchema() throws {
        let json = #"{"schemaVersion":"plan_option_cards.v1","cards":[{"candidateID":"x","outcome":"y","benefits":[],"challenges":[]}]}"#
        let payload = try CoachStructuredOutputDecoder.decode(
            PlanOptionCardsPayload.self,
            from: json,
            expectedSchema: .planOptionCardsV1
        )
        #expect(payload.cards[0].outcome == "y")
    }

    @Test("request body builder embeds response schema")
    func requestBodyHasSchema() throws {
        let body = try GeminiRequestBuilder.planOptionCardsBody(
            systemInstructions: "test",
            userMessage: "candidates"
        )
        let data = try body.encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let config = try #require(object["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect(config["responseSchema"] != nil)
    }
}
