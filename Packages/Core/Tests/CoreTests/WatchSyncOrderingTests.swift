import Foundation
import Testing
@testable import Core

@Suite("WatchSyncOrdering")
struct WatchSyncOrderingTests {
    @Test("first payload for an origin is always accepted")
    func acceptFirst() {
        #expect(WatchSyncOrdering.shouldAccept(sequence: 1, sentAt: 100, previous: nil))
    }

    @Test("higher sequence wins")
    func higherSequence() {
        let previous = WatchSyncOriginWatermark(sequence: 5, sentAt: 100)
        #expect(WatchSyncOrdering.shouldAccept(sequence: 6, sentAt: 90, previous: previous))
        #expect(!WatchSyncOrdering.shouldAccept(sequence: 4, sentAt: 200, previous: previous))
    }

    @Test("same sequence keeps newer sentAt only")
    func sameSequenceUsesSentAt() {
        let previous = WatchSyncOriginWatermark(sequence: 3, sentAt: 100)
        #expect(WatchSyncOrdering.shouldAccept(sequence: 3, sentAt: 101, previous: previous))
        #expect(!WatchSyncOrdering.shouldAccept(sequence: 3, sentAt: 100, previous: previous))
        #expect(!WatchSyncOrdering.shouldAccept(sequence: 3, sentAt: 99, previous: previous))
    }

    @Test("watermark factory matches fields")
    func watermarkFactory() {
        let mark = WatchSyncOrdering.watermark(sequence: 9, sentAt: 42)
        #expect(mark.sequence == 9)
        #expect(mark.sentAt == 42)
    }
}
