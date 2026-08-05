import Foundation
import Testing
@testable import Core

@Suite("WatchCompleteSetOutbox")
struct WatchCompleteSetOutboxTests {
    @Test("enqueue, markSent, markAcked, and survives relaunch via file")
    func enqueueFlushAckSurvivesRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchOutboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("outbox.json")
        let outbox = WatchCompleteSetOutbox(fileURL: fileURL)

        let entry = outbox.enqueue(
            eventID: "evt-1",
            sessionExerciseID: "ex-1",
            setID: "set-1",
            createdAt: 1_000
        )
        #expect(entry.eventID == "evt-1")
        #expect(outbox.depth == 1)
        #expect(outbox.hasUnacked(setID: "set-1"))
        #expect(outbox.pending.first?.status == .pending)

        outbox.markSent(eventID: "evt-1")
        #expect(outbox.pending.first?.status == .sent)
        #expect(outbox.pending.first?.attemptCount == 1)

        // Simulate Watch process relaunch from the same file.
        let relaunched = WatchCompleteSetOutbox(fileURL: fileURL)
        #expect(relaunched.depth == 1)
        #expect(relaunched.pending.first?.eventID == "evt-1")
        #expect(relaunched.pending.first?.status == .sent)
        #expect(relaunched.pending.first?.attemptCount == 1)

        relaunched.markAcked(eventID: "evt-1")
        #expect(relaunched.depth == 0)
        #expect(!relaunched.hasUnacked(setID: "set-1"))

        let afterAck = WatchCompleteSetOutbox(fileURL: fileURL)
        #expect(afterAck.depth == 0)
    }

    @Test("pending returns oldest first")
    func pendingOldestFirst() {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("outbox-order-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let outbox = WatchCompleteSetOutbox(fileURL: fileURL)
        _ = outbox.enqueue(
            eventID: "later",
            sessionExerciseID: "ex",
            setID: "set-b",
            createdAt: 200
        )
        _ = outbox.enqueue(
            eventID: "earlier",
            sessionExerciseID: "ex",
            setID: "set-a",
            createdAt: 100
        )

        #expect(outbox.pending.map(\.eventID) == ["earlier", "later"])
    }
}
