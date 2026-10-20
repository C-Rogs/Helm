import Testing
@testable import HealthKitIngest

@Suite("Body fat latest facts")
struct BodyFatLatestFactsTests {
    @Test("grounded reply quotes HealthKit and store when they differ")
    func groundedReplyQuotesBoth() {
        let facts = BodyFatLatestFacts(
            hkDay: "2026-08-31",
            hkPercent: 22.1,
            storeDay: "2026-08-10",
            storePercent: 24.4,
            hkReadableCount: 12
        )
        let reply = facts.groundedChatReply()
        #expect(reply.contains("22.1%"))
        #expect(reply.contains("2026-08-31"))
        #expect(reply.contains("24.4%"))
        #expect(reply.contains("2026-08-10"))
    }

    @Test("grounded reply tells the athlete to check scale sync when HealthKit is empty")
    func groundedReplyEmptyHealthKit() {
        let reply = BodyFatLatestFacts.empty.groundedChatReply()
        #expect(reply.contains("no Body Fat Percentage sample"))
        #expect(reply.contains("scale"))
        #expect(reply.contains("Body fat probe"))
    }

    @Test("trend tool lines are facts, not the canned chat sentence")
    func trendToolLinesAreNotChatCopy() {
        let facts = BodyFatLatestFacts(
            hkDay: "2026-10-20",
            hkPercent: 24.2,
            storeDay: "2026-10-20",
            storePercent: 24.2,
            hkReadableCount: 4,
            hkSource: "com.vt.vitafit"
        )
        let lines = facts.trendToolLines()
        #expect(lines.contains("hk_newest_percent=24.2"))
        #expect(lines.contains("hk_source=com.vt.vitafit"))
        #expect(!lines.contains("Apple Health newest"))
        #expect(lines != facts.groundedChatReply())
    }
}
