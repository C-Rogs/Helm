import Core
import Foundation

// MARK: - Drift policy (normative)
//
// When a planned session is completed on `actualDay` relative to `plannedDay`:
//
// | Days late | Action |
// |-----------|--------|
// | 0         | keep: mark completed on the planned day |
// | 1         | shift: move the session to `actualDay` |
// | 2         | shift: move session; trim pending accessory load by 20% |
// | 3–4       | shift when `plannedDay` and `actualDay` share the same ISO week; otherwise skip |
// | 5+        | late completion on `actualDay`; skip earlier pending sessions; no volume backfill |
//
// Out-of-order logging: completing a session while earlier sessions are still pending skips every earlier pending session.
//
// ACWR guard: when acute:chronic workload ratio exceeds 1.5, downgrade `shift` and `restructure` to `skip` for the completion being resolved.

enum HelmDayMath {
    static func daysLate(plannedDay: HelmDay, actualDay: HelmDay, calendar: Calendar) -> Int {
        guard plannedDay <= actualDay else { return 0 }
        var count = 0
        var cursor = plannedDay
        while cursor < actualDay {
            cursor = cursor.adding(days: 1, calendar: calendar)
            count += 1
        }
        return count
    }

    static func sameISOWeek(_ lhs: HelmDay, _ rhs: HelmDay, calendar: Calendar) -> Bool {
        guard
            let left = calendar.date(from: lhs.dateComponents()),
            let right = calendar.date(from: rhs.dateComponents())
        else {
            return false
        }
        let leftWeek = calendar.component(.weekOfYear, from: left)
        let rightWeek = calendar.component(.weekOfYear, from: right)
        let leftYear = calendar.component(.yearForWeekOfYear, from: left)
        let rightYear = calendar.component(.yearForWeekOfYear, from: right)
        return leftWeek == rightWeek && leftYear == rightYear
    }
}

enum AcuteChronicWorkload {
    static let guardThreshold = 1.5
    private static let acuteWindowDays = 7
    private static let chronicWindowDays = 28

    static func ratio(
        dailyLoads: [HelmDay: Double],
        asOf day: HelmDay,
        calendar: Calendar
    ) -> AcuteChronicWorkloadRatio {
        let acute = sumLoad(dailyLoads: dailyLoads, endingOn: day, windowDays: acuteWindowDays, calendar: calendar)
        let chronicTotal = sumLoad(
            dailyLoads: dailyLoads,
            endingOn: day,
            windowDays: chronicWindowDays,
            calendar: calendar
        )
        let chronicWeekly = chronicTotal / Double(chronicWindowDays / acuteWindowDays)
        return AcuteChronicWorkloadRatio(acuteLoad: acute, chronicWeeklyLoad: chronicWeekly)
    }

    private static func sumLoad(
        dailyLoads: [HelmDay: Double],
        endingOn day: HelmDay,
        windowDays: Int,
        calendar: Calendar
    ) -> Double {
        var total = 0.0
        for offset in 0..<windowDays {
            let helmDay = day.adding(days: -offset, calendar: calendar)
            total += dailyLoads[helmDay, default: 0]
        }
        return total
    }
}

enum DriftPolicyEngine {
    static let accessoryTrimFraction = 0.20

  static func resolveDrift(
        planned: PlannedCalendar,
        actual: ActualCalendar,
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> PlanAdjustment {
        var updated = planned
        var resolutions: [SessionDriftResolution] = []

        guard let log = actual.completedLog else {
            return PlanAdjustment(resolutions: [], updatedCalendar: updated)
        }

        guard let index = updated.sessions.firstIndex(where: { $0.id == log.plannedSessionID }) else {
            return PlanAdjustment(resolutions: [], updatedCalendar: updated)
        }

        let workloadRatio = AcuteChronicWorkload.ratio(
            dailyLoads: actual.dailyLoadByDay,
            asOf: log.actualDay,
            calendar: calendar
        )

        // Out-of-order: skip earlier pending sessions.
        let targetPlannedDay = updated.sessions[index].plannedDay
        for i in updated.sessions.indices where updated.sessions[i].plannedDay < targetPlannedDay {
            if updated.sessions[i].status == .pending {
                updated.sessions[i].status = .skipped
                resolutions.append(
                    SessionDriftResolution(
                        sessionID: updated.sessions[i].id,
                        action: .skip,
                        fromDay: updated.sessions[i].plannedDay
                    )
                )
            }
        }

        let session = updated.sessions[index]
        let lateness = HelmDayMath.daysLate(
            plannedDay: session.plannedDay,
            actualDay: log.actualDay,
            calendar: calendar
        )

        var action = baseAction(
            lateness: lateness,
            plannedDay: session.plannedDay,
            actualDay: log.actualDay,
            calendar: calendar
        )

        if workloadRatio.exceedsGuardThreshold, action == .shift || action == .restructure {
            action = .skip
        }

        switch action {
        case .keep:
            updated.sessions[index].status = .completed
            resolutions.append(
                SessionDriftResolution(
                    sessionID: session.id,
                    action: .keep,
                    fromDay: session.plannedDay,
                    toDay: session.plannedDay
                )
            )

        case .shift:
            if lateness == 2 {
                trimAccessoryLoadOnPending(in: &updated, excluding: index)
            }
            updated.sessions[index].plannedDay = log.actualDay
            updated.sessions[index].status = .shifted
            resolutions.append(
                SessionDriftResolution(
                    sessionID: session.id,
                    action: .shift,
                    fromDay: session.plannedDay,
                    toDay: log.actualDay
                )
            )

        case .skip:
            updated.sessions[index].status = .skipped
            resolutions.append(
                SessionDriftResolution(
                    sessionID: session.id,
                    action: .skip,
                    fromDay: session.plannedDay
                )
            )

        case .restructure:
            updated.sessions[index].plannedDay = log.actualDay
            updated.sessions[index].status = .completed
            resolutions.append(
                SessionDriftResolution(
                    sessionID: session.id,
                    action: .restructure,
                    fromDay: session.plannedDay,
                    toDay: log.actualDay
                )
            )
        }

        return PlanAdjustment(
            resolutions: resolutions,
            updatedCalendar: updated,
            workloadRatio: workloadRatio
        )
    }

    private static func baseAction(
        lateness: Int,
        plannedDay: HelmDay,
        actualDay: HelmDay,
        calendar: Calendar
    ) -> DriftAction {
        switch lateness {
        case 0:
            return .keep
        case 1, 2:
            return .shift
        case 3...4:
            if HelmDayMath.sameISOWeek(plannedDay, actualDay, calendar: calendar) {
                return .shift
            }
            return .skip
        default:
            return .restructure
        }
    }

    private static func trimAccessoryLoadOnPending(
        in planned: inout PlannedCalendar,
        excluding completedIndex: Int,
        fraction: Double = accessoryTrimFraction
    ) {
        let scale = max(0, 1 - fraction)
        for index in planned.sessions.indices where index != completedIndex {
            guard planned.sessions[index].status == .pending else { continue }
            planned.sessions[index].trainingLoad *= scale
        }
    }
}
