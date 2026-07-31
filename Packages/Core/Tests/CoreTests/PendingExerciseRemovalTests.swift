import Foundation
import Testing
@testable import Core

@Suite("Pending exercise removal")
struct PendingExerciseRemovalTests {
    @Test("confirm with presenting ID removes even after Binding cancel race")
    func presentingIDSurvivesCancelRace() {
        var pending = PendingExerciseRemoval()
        pending.request("ex-1")
        pending.cancel()
        let id = pending.confirm(presentingID: "ex-1")
        #expect(id == "ex-1")
        #expect(pending.pendingID == nil)
    }

    @Test("confirm falls back to pending when presenting ID missing")
    func fallsBackToPending() {
        var pending = PendingExerciseRemoval()
        pending.request("ex-2")
        let id = pending.confirm(presentingID: nil)
        #expect(id == "ex-2")
        #expect(pending.pendingID == nil)
    }

    @Test("confirm with neither ID returns nil")
    func nilWhenNothingToRemove() {
        var pending = PendingExerciseRemoval()
        #expect(pending.confirm(presentingID: nil) == nil)
    }
}
