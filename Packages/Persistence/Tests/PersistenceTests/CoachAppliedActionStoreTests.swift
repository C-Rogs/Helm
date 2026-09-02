import Foundation
import Testing
@testable import Persistence

@Suite("Coach applied action store")
struct CoachAppliedActionStoreTests {
    @Test("insert fetch and mark undone after v25 migration")
    func roundTripUndo() throws {
        let store = try PersistenceStore.inMemory()
        let snapshot = MealDeleteSnapshot(items: [])
        let json = (try? JSONEncoder().encode(snapshot)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let action = CoachAppliedAction(
            messageID: "msg-undo",
            kind: .mealDelete,
            snapshotJSON: json
        )

        try store.coachAppliedActions.insert(action)
        let loaded = try store.coachAppliedActions.fetchUndoable(messageID: "msg-undo")
        #expect(loaded?.id == action.id)
        #expect(loaded?.isUndoable == true)

        try store.coachAppliedActions.markUndone(id: action.id)
        #expect(try store.coachAppliedActions.fetchUndoable(messageID: "msg-undo") == nil)
        #expect(try store.coachAppliedActions.fetch(id: action.id)?.undoneAt != nil)
    }
}
