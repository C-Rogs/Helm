import Foundation
import Testing
@testable import Persistence
import Core

@Suite("BriefStore")
struct BriefStoreTests {
    @Test("daily brief round trips")
    func roundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let day = HelmDay(year: 2026, month: 7, day: 23)
        let brief = StoredDailyBrief(
            helmDay: day,
            inputFingerprint: "abc123",
            engineText: "ARC 72. Session: 18 sets.",
            narrationText: "Recovery looks solid. Hit today's compounds.",
            citationIDs: ["ev-chest-1"],
            source: .coach,
            promptVersion: "brief.prompt.v1",
            schemaVersion: "brief.v1",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        try store.brief.save(brief)
        let fetched = try store.brief.fetch(for: day)

        #expect(fetched == brief)
    }
}
