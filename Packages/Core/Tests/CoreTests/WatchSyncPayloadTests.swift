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
            sentAt: 1_723_456_789,
            messageKind: .readiness,
            readinessScore: 64,
            readinessBand: "balanced",
            briefSummary: "ARC 64. Hold steady."
        )

        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())

        #expect(restored == payload)
    }

    @Test("legacy ping payload decodes without readiness fields")
    func legacyPingPayload() throws {
        let json = """
        {"origin":"phone","sequence":1,"helmDay":"2026-07-21","sentAt":1723456789}
        """
        let data = try #require(json.data(using: .utf8))
        let payload = try JSONDecoder().decode(WatchSyncPayload.self, from: data)

        #expect(payload.messageKind == .ping)
        #expect(payload.readinessScore == nil)
    }

    @Test("restEnded round-trips")
    func restEndedRoundTrip() {
        let payload = WatchSyncPayload(
            origin: .phone,
            sequence: 3,
            helmDay: HelmDay(year: 2026, month: 7, day: 31),
            sentAt: 1_723_456_789,
            messageKind: .restEnded
        )
        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())
        #expect(restored == payload)
        #expect(restored?.messageKind == .restEnded)
    }

    @Test("completeSet and companion IDs round-trip")
    func completeSetRoundTrip() {
        let payload = WatchSyncPayload(
            origin: .watch,
            sequence: 9,
            helmDay: HelmDay(year: 2026, month: 8, day: 2),
            sentAt: 1_723_456_789,
            messageKind: .completeSet,
            companionSessionExerciseID: "ex-1",
            companionSetID: "set-2"
        )
        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())
        #expect(restored == payload)
        #expect(restored?.companionSessionExerciseID == "ex-1")
        #expect(restored?.companionSetID == "set-2")
    }

    @Test("workoutCompanion save flag round-trips")
    func companionSaveFlagRoundTrip() {
        let payload = WatchSyncPayload(
            origin: .phone,
            sequence: 4,
            helmDay: HelmDay(year: 2026, month: 8, day: 2),
            sentAt: 1_723_456_789,
            messageKind: .workoutCompanion,
            workoutCompanionActive: false,
            companionSaveWatchWorkout: true
        )
        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())
        #expect(restored == payload)
        #expect(restored?.companionSaveWatchWorkout == true)
    }

    @Test("diagnostic event round-trips")
    func diagnosticRoundTrip() {
        let payload = WatchSyncPayload(
            origin: .watch,
            sequence: 11,
            helmDay: HelmDay(year: 2026, month: 8, day: 4),
            sentAt: 1_723_456_789,
            messageKind: .diagnostic,
            diagnosticEvent: WatchCompanionDiagnosticEvent.watchHandleBegin.rawValue,
            diagnosticDetail: "activity=strength"
        )
        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())
        #expect(restored == payload)
        #expect(restored?.diagnosticEvent == "watch.handle.begin")
        #expect(restored?.diagnosticDetail == "activity=strength")
    }
}
