import Foundation
import Testing
@testable import CoachLLM

@Suite("ChartPayload")
struct ChartPayloadTests {
    @Test("decodes chart.v1 fixture")
    func decodesFixture() throws {
        let json = try fixtureText(named: "chart_v1")
        let payload = try JSONDecoder().decode(ChartPayload.self, from: Data(json.utf8))
        #expect(payload.schemaVersion == CoachOutputSchemaVersion.chartV1.rawValue)
        #expect(payload.title == "Hard sets")
        #expect(payload.points.count == 5)
        #expect(payload.points[0].label == "Mon")
        #expect(payload.points[0].value == 12)
    }

    @Test("parses embedded chart block from assistant text")
    func parsesEmbeddedBlock() throws {
        let block = [
            #"{"schemaVersion":"chart.v1","reply":"Hard sets.","title":"Hard sets","unit":"sets","#,
            #""points":[{"label":"Mon","value":12},{"label":"Tue","value":8}]}"#
        ].joined()
        let text = "Weekly hard sets.\n\(block)"
        let payload = try #require(ChartPayloadParser.parse(from: text))
        #expect(payload.points.map(\.label) == ["Mon", "Tue"])
    }

    @Test("strips chart JSON from assistant text")
    func stripsJSONFromChatText() {
        let block = #"{"schemaVersion":"chart.v1","reply":"Hard sets.","title":"Hard sets","unit":"sets","points":[{"label":"Mon","value":12}]}"#
        let text = "Weekly hard sets.\n\(block)"
        let display = CoachChatTextFormatter.userFacingText(from: text)
        #expect(display == "Weekly hard sets.")
    }

    @Test("persisted assistant text keeps chart JSON")
    func persistedTextKeepsChartJSON() throws {
        let block = #"{"schemaVersion":"chart.v1","reply":"Hard sets.","title":"Hard sets","unit":"sets","points":[{"label":"Mon","value":12}]}"#
        let persisted = CoachChatPersistedAssistantText.make(assembled: block)
        #expect(ChartPayloadParser.parse(from: persisted) != nil)
        #expect(CoachChatTextFormatter.userFacingText(from: persisted) == "Hard sets.")
    }

    @Test("chart bubble snapshot is byte-stable")
    func chartBubbleSnapshot() throws {
        let json = try fixtureText(named: "chart_v1")
        let payload = try JSONDecoder().decode(ChartPayload.self, from: Data(json.utf8))
        let text = CoachChatChartSnapshot.text(for: payload)
        #expect(text == expectedChartSnapshot)
        #expect(text == CoachChatChartSnapshot.text(for: payload))
        #expect(text.contains("Hard sets"))
        #expect(text.contains("Mon=12"))
    }

    private func fixtureText(named name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            Issue.record("Missing fixture \(name).json")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private let expectedChartSnapshot = """
# Chart
## Title
Hard sets
## Unit
sets
## Points
- Mon=12
- Tue=8
- Wed=14
- Thu=0
- Fri=10
"""
