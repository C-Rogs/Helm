import Foundation
import Persistence
import Testing

@Suite("AppMetadataStore")
struct AppMetadataStoreTests {
    @Test("set and fetch metadata values")
    func roundTrip() throws {
        let store = try PersistenceStore.inMemory()
        try store.appMetadata.setValue("2026-07-23", forKey: "brief_intent_missed_day")
        #expect(try store.appMetadata.value(forKey: "brief_intent_missed_day") == "2026-07-23")

        try store.appMetadata.setValue(nil, forKey: "brief_intent_missed_day")
        #expect(try store.appMetadata.value(forKey: "brief_intent_missed_day") == nil)
    }
}
