import Foundation
import Testing
@testable import Persistence

@Suite("Coach chat confirmation store")
struct CoachChatConfirmationStoreTests {
    @Test("insert fetch and resolve after v29 migration")
    func insertFetchResolve() throws {
        let store = try PersistenceStore.inMemory()
        let record = CoachChatConfirmation(
            messageID: "msg-1",
            title: "Log snack",
            detail: "Apple · 95 kcal",
            confirmLabel: "Log meal",
            cancelLabel: "Cancel"
        )
        try store.coachChatConfirmations.insert(record)

        let fetched = try store.coachChatConfirmations.fetch(messageID: "msg-1")
        #expect(fetched?.title == "Log snack")
        #expect(fetched?.outcome == .pending)

        try store.coachChatConfirmations.markResolved(
            messageID: "msg-1",
            outcome: .confirmed,
            selectedLabel: "Log meal"
        )
        let resolved = try store.coachChatConfirmations.fetch(messageID: "msg-1")
        #expect(resolved?.outcome == .confirmed)
        #expect(resolved?.selectedLabel == "Log meal")
        #expect(resolved?.resolvedAt != nil)
    }
}
