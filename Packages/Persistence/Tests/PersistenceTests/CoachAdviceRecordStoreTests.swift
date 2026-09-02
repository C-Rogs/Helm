import Foundation
import Testing
@testable import Persistence

@Suite("Coach advice record store")
struct CoachAdviceRecordStoreTests {
    @Test("insert and fetch round-trip after v24 migration")
    func roundTrip() throws {
        let store = try PersistenceStore.inMemory()
        let createdAt = Date(timeIntervalSince1970: 1_788_350_400)
        let record = CoachAdviceRecord(
            messageID: "msg-1",
            adviceType: .workoutStart,
            schemaVersion: "workout_start.v2",
            prescribedPayload: "{\"schemaVersion\":\"workout_start.v2\"}",
            state: .pending,
            helmDay: "2026-09-02",
            createdAt: createdAt
        )

        try store.coachAdviceRecords.insert(record)
        let loaded = try store.coachAdviceRecords.fetchByMessageID("msg-1")

        #expect(loaded?.id == record.id)
        #expect(loaded?.adviceType == .workoutStart)
        #expect(loaded?.state == .pending)
        #expect(loaded?.helmDay == "2026-09-02")
        #expect(loaded?.schemaVersion == "workout_start.v2")
        #expect(abs((loaded?.createdAt.timeIntervalSince1970 ?? 0) - createdAt.timeIntervalSince1970) < 0.001)
    }

    @Test("supersede pending leaves the newest row")
    func supersedePending() throws {
        let store = try PersistenceStore.inMemory()
        let older = CoachAdviceRecord(
            messageID: "msg-old",
            adviceType: .workoutStart,
            schemaVersion: "workout_start.v2",
            prescribedPayload: "{}",
            helmDay: "2026-09-02"
        )
        let newest = CoachAdviceRecord(
            messageID: "msg-new",
            adviceType: .workoutStart,
            schemaVersion: "workout_start.v2",
            prescribedPayload: "{}",
            helmDay: "2026-09-02"
        )
        try store.coachAdviceRecords.insert(older)
        try store.coachAdviceRecords.insert(newest)
        try store.coachAdviceRecords.supersedePending(type: .workoutStart, excluding: newest.messageID)

        let pending = try store.coachAdviceRecords.fetch(
            helmDay: "2026-09-02",
            adviceType: .workoutStart,
            state: .pending
        )
        #expect(pending.map(\.messageID) == ["msg-new"])
        #expect(try store.coachAdviceRecords.fetchByMessageID("msg-old")?.state == .superseded)
    }
}
