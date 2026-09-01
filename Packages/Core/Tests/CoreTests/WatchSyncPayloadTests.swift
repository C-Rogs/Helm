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
            companionSetID: "set-2",
            eventID: "evt-abc"
        )
        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())
        #expect(restored == payload)
        #expect(restored?.companionSessionExerciseID == "ex-1")
        #expect(restored?.companionSetID == "set-2")
        #expect(restored?.eventID == "evt-abc")
    }

    @Test("completeSetAck eventID round-trips")
    func completeSetAckRoundTrip() {
        let payload = WatchSyncPayload(
            origin: .phone,
            sequence: 10,
            helmDay: HelmDay(year: 2026, month: 8, day: 4),
            sentAt: 1_723_456_789,
            messageKind: .completeSetAck,
            eventID: "evt-ack-1"
        )
        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())
        #expect(restored == payload)
        #expect(restored?.messageKind == .completeSetAck)
        #expect(restored?.eventID == "evt-ack-1")
    }

    @Test("legacy completeSet without eventID still decodes")
    func legacyCompleteSetWithoutEventID() throws {
        let json = """
        {"origin":"watch","sequence":2,"helmDay":"2026-08-04","sentAt":1723456789,"messageKind":"completeSet","companionSessionExerciseID":"ex","companionSetID":"set"}
        """
        let data = try #require(json.data(using: .utf8))
        let payload = try JSONDecoder().decode(WatchSyncPayload.self, from: data)
        #expect(payload.eventID == nil)
        #expect(payload.messageKind == .completeSet)
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

    @Test("companion session start time round-trips")
    func companionSessionStartedAtRoundTrip() {
        let payload = WatchSyncPayload(
            origin: .phone,
            sequence: 12,
            helmDay: HelmDay(year: 2026, month: 8, day: 4),
            sentAt: 1_723_456_789,
            messageKind: .workoutCompanion,
            workoutCompanionActive: true,
            companionSessionStartedAt: 1_723_456_000
        )
        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())
        #expect(restored?.companionSessionStartedAt == 1_723_456_000)
    }

    @Test("companion rest end and activity type round-trip")
    func companionRestAndActivityRoundTrip() {
        let payload = WatchSyncPayload(
            origin: .phone,
            sequence: 13,
            helmDay: HelmDay(year: 2026, month: 9, day: 1),
            sentAt: 1_723_456_789,
            messageKind: .workoutCompanion,
            workoutCompanionActive: true,
            companionRestEndsAt: 1_723_457_000,
            companionActivityTypeRawValue: 37
        )
        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())
        #expect(restored?.companionRestEndsAt == 1_723_457_000)
        #expect(restored?.companionActivityTypeRawValue == 37)
    }

    @Test("legacy workoutCompanion without rest/activity still decodes")
    func legacyCompanionWithoutRest() throws {
        let json = """
        {"origin":"phone","sequence":1,"helmDay":"2026-09-01","sentAt":1723456789,"messageKind":"workoutCompanion","workoutCompanionActive":true}
        """
        let data = try #require(json.data(using: .utf8))
        let payload = try JSONDecoder().decode(WatchSyncPayload.self, from: data)
        #expect(payload.companionRestEndsAt == nil)
        #expect(payload.companionActivityTypeRawValue == nil)
        #expect(payload.watchWorkoutActive == nil)
        #expect(payload.companionRestDeltaSeconds == nil)
    }

    @Test("watch workout flag and rest adjust round-trip")
    func watchWorkoutAndRestAdjustRoundTrip() {
        let payload = WatchSyncPayload(
            origin: .watch,
            sequence: 14,
            helmDay: HelmDay(year: 2026, month: 9, day: 1),
            sentAt: 1_723_456_789,
            messageKind: .restAdjust,
            watchWorkoutActive: true,
            companionRestDeltaSeconds: 15
        )
        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())
        #expect(restored?.messageKind == .restAdjust)
        #expect(restored?.watchWorkoutActive == true)
        #expect(restored?.companionRestDeltaSeconds == 15)
    }

    @Test("restSkip round-trips")
    func restSkipRoundTrip() {
        let payload = WatchSyncPayload(
            origin: .watch,
            sequence: 15,
            helmDay: HelmDay(year: 2026, month: 9, day: 1),
            sentAt: 1_723_456_789,
            messageKind: .restSkip
        )
        let restored = WatchSyncPayload.from(applicationContext: payload.applicationContext())
        #expect(restored?.messageKind == .restSkip)
    }
}
