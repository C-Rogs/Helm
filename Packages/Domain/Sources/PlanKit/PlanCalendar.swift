import Core
import Foundation

/// Lifecycle of a planned training session on the calendar.
public enum PlannedSessionStatus: String, Sendable, Hashable, Codable {
    case pending
    case completed
    case skipped
    case shifted
}

/// A single prescribed session anchored to a logical day.
public struct PlannedSession: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public var plannedDay: HelmDay
    public var status: PlannedSessionStatus
    /// Edwards-style training load used for ACWR guards.
    public var trainingLoad: Double

    public init(
        id: String,
        plannedDay: HelmDay,
        status: PlannedSessionStatus = .pending,
        trainingLoad: Double
    ) {
        self.id = id
        self.plannedDay = plannedDay
        self.status = status
        self.trainingLoad = trainingLoad
    }
}

/// The forward-looking plan: ordered sessions the engine expects to run.
public struct PlannedCalendar: Sendable, Hashable, Codable {
    public var sessions: [PlannedSession]

    public init(sessions: [PlannedSession] = []) {
        self.sessions = sessions
    }
}

/// A session that actually happened (or is being logged now).
public struct ActualSessionLog: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let plannedSessionID: String
    public let actualDay: HelmDay
    public let trainingLoad: Double

    public init(
        id: String,
        plannedSessionID: String,
        actualDay: HelmDay,
        trainingLoad: Double
    ) {
        self.id = id
        self.plannedSessionID = plannedSessionID
        self.actualDay = actualDay
        self.trainingLoad = trainingLoad
    }
}

/// Logged reality plus historical daily loads for workload guards.
public struct ActualCalendar: Sendable, Hashable, Codable {
    /// Rolling daily training load totals keyed by Helm day.
    public var dailyLoadByDay: [HelmDay: Double]
    /// The session completion event driving this drift resolution pass.
    public var completedLog: ActualSessionLog?

    public init(dailyLoadByDay: [HelmDay: Double] = [:], completedLog: ActualSessionLog? = nil) {
        self.dailyLoadByDay = dailyLoadByDay
        self.completedLog = completedLog
    }
}

/// Deterministic adjustment chosen for a drifting session.
public enum DriftAction: String, Sendable, Hashable, Codable {
    case keep
    case shift
    case skip
    case restructure
}

/// Per-session outcome of a drift resolution pass.
public struct SessionDriftResolution: Sendable, Hashable, Codable {
    public let sessionID: String
    public let action: DriftAction
    public let fromDay: HelmDay
    public let toDay: HelmDay?

    public init(sessionID: String, action: DriftAction, fromDay: HelmDay, toDay: HelmDay? = nil) {
        self.sessionID = sessionID
        self.action = action
        self.fromDay = fromDay
        self.toDay = toDay
    }
}

/// Acute-to-chronic workload ratio snapshot.
public struct AcuteChronicWorkloadRatio: Sendable, Hashable, Codable {
    public let acuteLoad: Double
    public let chronicWeeklyLoad: Double
    public let ratio: Double

    public init(acuteLoad: Double, chronicWeeklyLoad: Double) {
        self.acuteLoad = acuteLoad
        self.chronicWeeklyLoad = chronicWeeklyLoad
        if chronicWeeklyLoad > 0 {
            ratio = acuteLoad / chronicWeeklyLoad
        } else {
            ratio = 0
        }
    }

    public var exceedsGuardThreshold: Bool {
        ratio > AcuteChronicWorkload.guardThreshold
    }
}

/// Updated plan state plus the resolutions that produced it.
public struct PlanAdjustment: Sendable, Hashable, Codable {
    public var resolutions: [SessionDriftResolution]
    public var updatedCalendar: PlannedCalendar
    public var workloadRatio: AcuteChronicWorkloadRatio?

    public init(
        resolutions: [SessionDriftResolution],
        updatedCalendar: PlannedCalendar,
        workloadRatio: AcuteChronicWorkloadRatio? = nil
    ) {
        self.resolutions = resolutions
        self.updatedCalendar = updatedCalendar
        self.workloadRatio = workloadRatio
    }
}
