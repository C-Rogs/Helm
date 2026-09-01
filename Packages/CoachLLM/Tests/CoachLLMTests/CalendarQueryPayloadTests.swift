import CoachLLM
import Foundation
import Testing

@Suite("CalendarQueryPayload")
struct CalendarQueryPayloadTests {
    @Test("parses calendar_query payload")
    func parsesQuery() {
        let text = """
        Checking the diary.
        {"schemaVersion":"calendar_query.v1","queryType":"today"}
        """
        let payload = CalendarQueryPayloadParser.parse(from: text)
        #expect(payload?.queryType == .today)
    }

    @Test("accepts flexible queryType aliases")
    func flexibleQueryType() throws {
        let data = """
        {"schemaVersion":"calendar_query.v1","queryType":"week_ahead","lookbackDays":"7"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(CalendarQueryPayload.self, from: data)
        #expect(payload.queryType == .weekAhead)
        #expect(payload.lookbackDays == 7)
    }

    @Test("decodes search and lookaheadDays")
    func searchAndLookahead() throws {
        let data = """
        {"schemaVersion":"calendar_query.v1","queryType":"search","search":"Italy","lookaheadDays":"180"}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(CalendarQueryPayload.self, from: data)
        #expect(payload.queryType == .range)
        #expect(payload.search == "Italy")
        #expect(payload.lookaheadDays == 180)
    }

    @Test("blank search becomes nil")
    func blankSearch() throws {
        let data = """
        {"schemaVersion":"calendar_query.v1","queryType":"range","search":"  "}
        """.data(using: .utf8)!
        let payload = try JSONDecoder().decode(CalendarQueryPayload.self, from: data)
        #expect(payload.search == nil)
    }

    @Test("function call args decode search")
    func functionCallSearch() throws {
        let call = CoachLLMFunctionCall(
            name: CoachCatalogToolName.calendarQuery.rawValue,
            arguments: [
                "queryType": "range",
                "search": "Italy",
                "lookaheadDays": 180
            ]
        )
        let payload = try #require(CoachCatalogQueryDecoder.calendar(from: [call]))
        #expect(payload.search == "Italy")
        #expect(payload.lookaheadDays == 180)
        #expect(payload.queryType == .range)
    }
}
