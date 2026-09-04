import CoachLLM
import Foundation
import Testing

@Suite("PatternQueryPayload")
struct PatternQueryPayloadTests {
    @Test("parses pattern_query payload")
    func parsesQuery() {
        let text = """
        Checking patterns.
        {"schemaVersion":"pattern_query.v1","status":"stable","field":"alcohol"}
        """
        let payload = PatternQueryPayloadParser.parse(from: text)
        #expect(payload?.status == .stable)
        #expect(payload?.field == "alcohol")
    }

    @Test("queryType alias maps to status")
    func queryTypeAlias() throws {
        let data = """
        {"schemaVersion":"pattern_query.v1","queryType":"prior_seed"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(PatternQueryPayload.self, from: data)
        #expect(payload.status == .priorSeed)
        #expect(payload.field == nil)
    }
}

@Suite("PatternDiscoveryPayload")
struct PatternDiscoveryPayloadTests {
    @Test("decodes schema-only hypotheses")
    func decodesHypotheses() throws {
        let data = """
        {"schemaVersion":"pattern_discovery.v1","hypotheses":[{
          "id":"llm_alcohol_hrv",
          "exposureField":"alcohol",
          "exposureOp":"present",
          "outcomeField":"hrv_sdnn",
          "lag":1
        }]}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(PatternDiscoveryPayload.self, from: data)
        #expect(payload.schemaVersion == CoachOutputSchemaVersion.patternDiscoveryV1.rawValue)
        #expect(payload.hypotheses.count == 1)
        #expect(payload.hypotheses[0].exposureField == "alcohol")
        #expect(payload.hypotheses[0].lag == 1)
        #expect(payload.hypotheses[0].requireTrainingDay == false)
    }

    @Test("discovery schema caps K at 5")
    func schemaCap() {
        let schema = GeminiRequestBuilder.patternDiscoverySchema()
        let hypotheses = schema["properties"] as? [String: Any]
        let array = hypotheses?["hypotheses"] as? [String: Any]
        #expect(array?["maxItems"] as? Int == 5)
    }
}
