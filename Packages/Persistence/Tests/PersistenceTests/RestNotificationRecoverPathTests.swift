import Foundation
import Testing
@testable import Persistence

@Suite("Rest notification recover path")
struct RestNotificationRecoverPathTests {
    @Test("recover path handles missing session without force unwrap")
    func missingSessionOutcome() async throws {
        let persistence = try PersistenceStore.inMemory()
        let engine = ActiveSessionEngine(repository: persistence.activeSessions)
        let recovered = try await engine.recover()

        #expect(recovered == nil)
        let outcome = RestNotificationRecoveryPolicy.evaluate(
            expectedSessionID: "orphaned-session",
            activeSessionID: recovered?.session.id
        )
        #expect(outcome == .noActiveSession(expectedSessionID: "orphaned-session"))
    }
}
