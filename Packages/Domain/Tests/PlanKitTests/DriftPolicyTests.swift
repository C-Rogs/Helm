import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Drift policy")
struct DriftPolicyTests {
    private let calendar = Calendar(identifier: .iso8601)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> HelmDay {
        HelmDay(year: y, month: m, day: d)
    }

    @Test("on-time completion keeps session")
    func onTimeKeep() {
        let plannedDay = day(2026, 7, 20)
        let planned = PlannedCalendar(sessions: [
            PlannedSession(id: "a", plannedDay: plannedDay, trainingLoad: 80)
        ])
        let actual = ActualCalendar(completedLog: ActualSessionLog(
            id: "log-1",
            plannedSessionID: "a",
            actualDay: plannedDay,
            trainingLoad: 80
        ))

        let adjustment = PlanKit.resolveDrift(planned: planned, actual: actual, calendar: calendar)

        #expect(adjustment.resolutions.contains { $0.sessionID == "a" && $0.action == .keep })
        #expect(adjustment.updatedCalendar.sessions.first?.status == .completed)
    }

    @Test("two days late shifts session")
    func twoDaysLateShift() {
        let plannedDay = day(2026, 7, 20)
        let actualDay = day(2026, 7, 22)
        let planned = PlannedCalendar(sessions: [
            PlannedSession(id: "a", plannedDay: plannedDay, trainingLoad: 90)
        ])
        let actual = ActualCalendar(completedLog: ActualSessionLog(
            id: "log-1",
            plannedSessionID: "a",
            actualDay: actualDay,
            trainingLoad: 90
        ))

        let adjustment = PlanKit.resolveDrift(planned: planned, actual: actual, calendar: calendar)

        #expect(adjustment.resolutions.contains { $0.sessionID == "a" && $0.action == .shift })
        let session = adjustment.updatedCalendar.sessions.first
        #expect(session?.status == .shifted)
        #expect(session?.plannedDay == actualDay)
    }

    @Test("five days late restructures and redistributes load")
    func fiveDaysLateRestructure() {
        let plannedDay = day(2026, 7, 10)
        let actualDay = day(2026, 7, 15)
        let planned = PlannedCalendar(sessions: [
            PlannedSession(id: "late", plannedDay: plannedDay, trainingLoad: 100),
            PlannedSession(id: "future", plannedDay: day(2026, 7, 18), trainingLoad: 50)
        ])
        let actual = ActualCalendar(completedLog: ActualSessionLog(
            id: "log-1",
            plannedSessionID: "late",
            actualDay: actualDay,
            trainingLoad: 100
        ))

        let adjustment = PlanKit.resolveDrift(planned: planned, actual: actual, calendar: calendar)

        #expect(adjustment.resolutions.contains { $0.sessionID == "late" && $0.action == .restructure })
        let future = adjustment.updatedCalendar.sessions.first { $0.id == "future" }
        #expect(future?.trainingLoad == 150)
    }

    @Test("out-of-order completion skips earlier pending sessions")
    func outOfOrderSkip() {
        let planned = PlannedCalendar(sessions: [
            PlannedSession(id: "mon", plannedDay: day(2026, 7, 20), trainingLoad: 70),
            PlannedSession(id: "wed", plannedDay: day(2026, 7, 22), trainingLoad: 70),
            PlannedSession(id: "fri", plannedDay: day(2026, 7, 24), trainingLoad: 70)
        ])
        let actual = ActualCalendar(completedLog: ActualSessionLog(
            id: "log-fri",
            plannedSessionID: "fri",
            actualDay: day(2026, 7, 24),
            trainingLoad: 70
        ))

        let adjustment = PlanKit.resolveDrift(planned: planned, actual: actual, calendar: calendar)

        let statuses = Dictionary(uniqueKeysWithValues: adjustment.updatedCalendar.sessions.map { ($0.id, $0.status) })
        #expect(statuses["mon"] == .skipped)
        #expect(statuses["wed"] == .skipped)
        #expect(statuses["fri"] == .completed)
    }

    @Test("ACWR guard downgrades shift to skip")
    func acwrGuardDowngradesShift() {
        let plannedDay = day(2026, 7, 20)
        let actualDay = day(2026, 7, 22)
        var loads: [HelmDay: Double] = [:]
        for offset in 0..<7 {
            loads[actualDay.adding(days: -offset, calendar: calendar)] = 150
        }
        for offset in 7..<28 {
            loads[actualDay.adding(days: -offset, calendar: calendar)] = 50
        }
        let planned = PlannedCalendar(sessions: [
            PlannedSession(id: "a", plannedDay: plannedDay, trainingLoad: 50)
        ])
        let actual = ActualCalendar(dailyLoadByDay: loads, completedLog: ActualSessionLog(
            id: "log-1",
            plannedSessionID: "a",
            actualDay: actualDay,
            trainingLoad: 50
        ))

        let adjustment = PlanKit.resolveDrift(planned: planned, actual: actual, calendar: calendar)

        #expect(adjustment.workloadRatio?.exceedsGuardThreshold == true)
        #expect(adjustment.resolutions.contains { $0.sessionID == "a" && $0.action == .skip })
        #expect(adjustment.updatedCalendar.sessions.first?.status == .skipped)
    }

    @Test("acute chronic workload ratio computation")
    func acwrComputation() {
        let asOf = day(2026, 7, 28)
        var loads: [HelmDay: Double] = [:]
        for offset in 0..<7 {
            loads[asOf.adding(days: -offset, calendar: calendar)] = 70
        }
        for offset in 7..<28 {
            loads[asOf.adding(days: -offset, calendar: calendar)] = 30
        }

        let ratio = PlanKit.acuteChronicWorkloadRatio(dailyLoads: loads, asOf: asOf, calendar: calendar)

        #expect(ratio.acuteLoad == 490)
        #expect(ratio.chronicWeeklyLoad == 280)
        #expect(abs(ratio.ratio - 1.75) < 0.001)
    }
}
