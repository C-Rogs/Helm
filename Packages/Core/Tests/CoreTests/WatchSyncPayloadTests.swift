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
            sentAt: 1_723_456_789
        )

        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())

        #expect(restored == payload)
    }

    @Test("missing key returns nil")
    func missingKey() {
        #expect(WatchSyncPayload.from(applicationContext: [:]) == nil)
    }
}
