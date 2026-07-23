import Core
import Foundation
import Testing

@Suite("Helm complication readiness")
struct HelmComplicationReadinessTests {
    @Test("payload supplies complication score and brief deep link")
    func payloadSuppliesComplicationScore() {
        let payload = WatchSyncPayload(
            origin: .phone,
            sequence: 3,
            helmDay: HelmDay(year: 2026, month: 7, day: 23),
            sentAt: 1_723_456_789,
            messageKind: .readiness,
            readinessScore: 72,
            readinessBand: "balanced",
            briefSummary: "ARC 72. Upper body at reduced volume."
        )

        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())

        #expect(restored?.readinessScore == 72)
        #expect(restored?.readinessBand == "balanced")
        #expect(restored?.briefSummary?.contains("ARC 72") == true)
        #expect(WatchSyncPayload.briefDeepLink == "helmwatch://brief")
    }

    @Test("complication entry formats score for display")
    func complicationEntryFormatting() {
        let scored = HelmComplicationEntry(date: .now, score: 58, band: "balanced")
        let missing = HelmComplicationEntry(date: .now, score: nil, band: nil)

        #expect(scored.displayScore == "58")
        #expect(missing.displayScore == "--")
    }
}

struct HelmComplicationEntry {
    let date: Date
    let score: Int?
    let band: String?

    var displayScore: String {
        guard let score else { return "--" }
        return "\(score)"
    }
}
