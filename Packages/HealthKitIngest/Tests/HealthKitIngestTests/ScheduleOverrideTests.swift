import CoachLLM
import Core
import Foundation
import Persistence
import PlanKit
import Testing
@testable import HealthKitIngest

@Suite("Schedule overrides")
struct ScheduleOverrideTests {
    @Test("weekStart is calendar Monday so Sunday stays in week")
    func weekStartKeepsSunday() {
        let sunday = HelmDay(year: 2026, month: 9, day: 6)
        let thursday = HelmDay(year: 2026, month: 9, day: 3)
        let start = PrescriptionHistoryBuilder.weekStart(containing: thursday, calendar: .current)
        #expect(start == HelmDay(year: 2026, month: 8, day: 31))
        let end = start.adding(days: 6)
        #expect(sunday >= start && sunday <= end)
    }
    @Test("defer push skips to legs in PPL")
    func deferPushPicksLegs() {
        let next = SchedulePlanner.nextDayKind(
            rotation: [.push, .pull, .legs],
            consumed: [],
            skipKinds: [.push]
        )
        #expect(next == .pull || next == .legs)
        let preferred = TrainingDayRecoveryMap.preferredKind(
            rotation: [.push, .pull, .legs],
            deferred: [.push, .pull],
            consumed: []
        )
        #expect(preferred == .legs)
    }

    @Test("arms region defers push and pull among PPL")
    func armsRegionDefersPush() {
        let kinds = TrainingDayRecoveryMap.deferredKinds(
            forRegion: "arms",
            among: [.push, .pull, .legs]
        )
        #expect(kinds.contains(.push))
        #expect(kinds.contains(.pull))
    }

    @Test("pin legs forces today and projects later push")
    func pinLegsProjectsWeek() {
        let today = HelmDay(year: 2026, month: 9, day: 7) // Monday
        let overrides = ScheduleWeekOverrides(
            pinnedByDay: [today: .legs],
            deferredKinds: [.push],
            reason: "Recovering arms"
        )
        let history = PrescriptionHistory(
            loggedSets: [],
            sessions: [],
            weekStart: today
        )
        let records = SchedulePlanner.plannedWorkoutRecords(
            startingAt: today,
            dayCount: 7,
            emphasis: nil,
            history: history,
            muscleMaps: [:],
            sessionsPerWeek: 3,
            dayKindRotation: [.push, .pull, .legs],
            overrides: overrides
        )
        #expect(records.isEmpty == false)
        let first = PlannedWorkoutSessionDecoder.decode(from: records[0].sessionJSON)
        #expect(first?.splitKind == TrainingDayKind.legs.rawValue
            || first?.splitLabel == "Legs")
        let kinds = records.compactMap {
            PlannedWorkoutSessionDecoder.decode(from: $0.sessionJSON)?.splitKind
        }
        #expect(kinds.contains(TrainingDayKind.push.rawValue) || kinds.contains("push"))
    }

    @Test("rest day override removes placement")
    func restDayRemovesPlacement() {
        let today = HelmDay(year: 2026, month: 9, day: 7)
        let overrides = ScheduleWeekOverrides(
            pinnedByDay: [today.adding(days: 1): .push],
            restDays: [today]
        )
        let history = PrescriptionHistory(loggedSets: [], sessions: [], weekStart: today)
        let days = SchedulePlanner.projectedTrainingDays(
            startingAt: today,
            dayCount: 7,
            sessionsPerWeek: 3,
            history: history,
            calendar: .current,
            overrides: overrides
        )
        #expect(days.contains(today) == false)
        #expect(days.contains(today.adding(days: 1)))
    }

    @Test("pins respect sessionsPerWeek after logged quota")
    func pinsRespectWeeklyQuota() {
        let today = HelmDay(year: 2026, month: 9, day: 7)
        let history = PrescriptionHistory(
            loggedSets: [],
            sessions: [
                WorkoutSession(helmDay: today, startedAt: Date()),
                WorkoutSession(helmDay: today.adding(days: 1), startedAt: Date()),
                WorkoutSession(helmDay: today.adding(days: 2), startedAt: Date())
            ],
            weekStart: today
        )
        let overrides = ScheduleWeekOverrides(
            pinnedByDay: [
                today.adding(days: 3): .push,
                today.adding(days: 4): .pull
            ]
        )
        let days = SchedulePlanner.projectedTrainingDays(
            startingAt: today,
            dayCount: 7,
            sessionsPerWeek: 3,
            history: history,
            calendar: .current,
            overrides: overrides
        )
        #expect(days.isEmpty)
    }

    @Test("completed days are not re-placed as pending")
    func completedDaysSkipped() {
        let today = HelmDay(year: 2026, month: 9, day: 7)
        let history = PrescriptionHistory(
            loggedSets: [],
            sessions: [
                WorkoutSession(helmDay: today, startedAt: Date())
            ],
            weekStart: today
        )
        let overrides = ScheduleWeekOverrides(pinnedByDay: [today: .legs])
        let days = SchedulePlanner.projectedTrainingDays(
            startingAt: today,
            dayCount: 7,
            sessionsPerWeek: 3,
            history: history,
            calendar: .current,
            overrides: overrides
        )
        #expect(days.contains(today) == false)
    }

    @Test("pinDay that already matches is redundant")
    func pinDayAlreadyAppliedIsRedundant() throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        let today = HelmDay(year: 2026, month: 9, day: 7)
        let weekStart = PrescriptionHistoryBuilder.weekStart(containing: today, calendar: .current)
        try store.scheduleOverrides.save(
            StoredScheduleOverrides(
                weekStartFormatted: weekStart.formatted,
                pinnedByDay: [today.formatted: TrainingDayKind.legs.rawValue],
                reason: "Pinned Legs"
            )
        )
        let payload = ScheduleAdjustmentPayload(
            action: .pinDay,
            pinKind: "legs",
            helmDay: today.formatted,
            reason: "Pin legs again"
        )
        #expect(ScheduleOverrideApplier.isRedundant(payload, persistence: store, today: today))
    }

    @Test("sameIntent ignores reply and reason wording")
    func sameIntentIgnoresWording() {
        let a = ScheduleAdjustmentPayload(
            action: .swapDays,
            reply: "Swapping Friday",
            dayA: "2026-09-04",
            dayB: "2026-09-05",
            reason: "Club night"
        )
        let b = ScheduleAdjustmentPayload(
            action: .swapDays,
            reply: "Different prose",
            dayA: "2026-09-04",
            dayB: "2026-09-05",
            reason: "Other reason"
        )
        #expect(ScheduleOverrideApplier.sameIntent(a, b))
        let c = ScheduleAdjustmentPayload(
            action: .swapDays,
            dayA: "2026-09-04",
            dayB: "2026-09-06"
        )
        #expect(!ScheduleOverrideApplier.sameIntent(a, c))
    }

    @Test("clear is redundant when overrides empty")
    func clearEmptyIsRedundant() throws {
        let store = try PersistenceStore.inMemory()
        try store.trainingPlan.save(.default)
        let today = HelmDay(year: 2026, month: 9, day: 7)
        let payload = ScheduleAdjustmentPayload(action: .clear)
        #expect(ScheduleOverrideApplier.isRedundant(payload, persistence: store, today: today))
    }
}
