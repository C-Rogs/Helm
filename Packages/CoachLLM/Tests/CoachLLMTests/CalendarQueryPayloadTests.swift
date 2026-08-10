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
}
