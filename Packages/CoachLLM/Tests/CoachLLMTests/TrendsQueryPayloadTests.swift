import CoachLLM
import Foundation
import Testing

@Suite("TrendsQueryPayload")
struct TrendsQueryPayloadTests {
    @Test("parses trends_query payload")
    func parsesQuery() {
        let text = """
        Looking at trends.
        {"schemaVersion":"trends_query.v1","queryType":"trimp","lookbackDays":30}
        """
        let payload = TrendsQueryPayloadParser.parse(from: text)
        #expect(payload?.queryType == .trimp)
        #expect(payload?.lookbackDays == 30)
    }

    @Test("accepts flexible queryType aliases")
    func flexibleQueryType() throws {
        let data = """
        {"schemaVersion":"trends_query.v1","queryType":"strength","exerciseName":"squat","lookbackDays":"14"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(TrendsQueryPayload.self, from: data)
        #expect(payload.queryType == .e1rm)
        #expect(payload.exerciseName == "squat")
        #expect(payload.lookbackDays == 14)
    }

    @Test("all query type works")
    func allQueryType() throws {
        let data = """
        {"schemaVersion":"trends_query.v1","queryType":"all"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(TrendsQueryPayload.self, from: data)
        #expect(payload.queryType == .all)
    }

    @Test("parses bodyFat query type")
    func bodyFatQueryType() throws {
        let data = """
        {"schemaVersion":"trends_query.v1","queryType":"body_fat","lookbackDays":90}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(TrendsQueryPayload.self, from: data)
        #expect(payload.queryType == .bodyFat)
        #expect(payload.lookbackDays == 90)
    }
}