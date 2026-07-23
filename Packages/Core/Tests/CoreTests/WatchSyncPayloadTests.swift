import Foundation
import Testing
@testable import Core

@Suite("WatchSyncPayload")
struct WatchSyncPayloadTests {
    @Test("round-trips through application context dictionary")
    func applicationContextRoundTrip() {
        let payload = WatchSyncPayload(
            origin: .phone,
            sequence: 7,
            helmDay: HelmDay(year: 2026, month: 7, day: 21),
            sentAt: 1_723_456_789,
            messageKind: .readiness,
            readinessScore: 64,
            readinessBand: "balanced",
            briefSummary: "ARC 64. Hold steady."
        )

        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())

        #expect(restored == payload)
    }

    @Test("legacy ping payload decodes without readiness fields")
    func legacyPingPayload() throws {
        let json = """
        {"origin":"phone","sequence":1,"helmDay":"2026-07-21","sentAt":1723456789}
        """
        let data = try #require(json.data(using: .utf8))
        let payload = try JSONDecoder().decode(WatchSyncPayload.self, from: data)

        #expect(payload.messageKind == .ping)
        #expect(payload.readinessScore == nil)
    }

    @Test("missing key returns nil")
    func missingKey() {
        #expect(WatchSyncPayload.from(applicationContext: [:]) == nil)
    }
}
