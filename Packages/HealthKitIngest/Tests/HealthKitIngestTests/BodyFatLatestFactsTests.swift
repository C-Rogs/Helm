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
}
