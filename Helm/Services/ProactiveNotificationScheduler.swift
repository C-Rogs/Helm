import Core
import Foundation
import HealthKitIngest
import Observation
import Persistence
import ReadinessKit
import UserNotifications

@MainActor
final class ProactiveNotificationScheduler {
    private let center: any NotificationScheduling
    private let persistence: PersistenceStore

    init(
        persistence: PersistenceStore,
        center: any NotificationScheduling = LiveNotificationCenter()
    ) {
        self.persistence = persistence
        self.center = center
    }

    func requestPermissionIfNeeded() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedulePreWorkoutPrimeIfNeeded(
        summary: PrescribedSessionSummary?,
        readinessScore: Int?,
        now: Date = .now,
        calendar: Calendar = .current
    ) async {
        let day = HelmDay.day(for: now, calendar: calendar)

        guard let summary else {
            await cancelPreWorkoutPrime(for: day)
            return
        }

        let recentSessions = (try? persistence.workoutSessions.listSummaries(limit: 24)) ?? []
        let workoutCompletedToday = recentSessions.contains { session in
            HelmDay.day(for: session.startedAt, calendar: calendar) == day
                && session.endedAt != nil
        }

        guard let plannedStart = PlannedSessionWindowEstimator.plannedStart(
            for: day,
            recentSessions: recentSessions,
            calendar: calendar
        ) else {
            return
        }

        let fireDate = PlannedSessionWindowEstimator.preWorkoutFireDate(plannedStart: plannedStart)
        guard PlannedSessionWindowEstimator.shouldSchedulePreWorkout(
            fireDate: fireDate,
            now: now,
            workoutCompletedToday: workoutCompletedToday
        ), let interval = PlannedSessionWindowEstimator.fireInterval(fireDate: fireDate, now: now) else {
            await cancelPreWorkoutPrime(for: day)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = PreWorkoutNotificationPlanner.title()
        content.body = PreWorkoutNotificationPlanner.body(
            summary: summary,
            readinessScore: readinessScore
        )
        content.sound = .default
        content.categoryIdentifier = PreWorkoutNotificationPlanner.notificationCategoryID
        content.userInfo = [
            PreWorkoutNotificationPlanner.helmDayUserInfoKey: day.formatted
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let identifier = PreWorkoutNotificationPlanner.notificationIdentifier(for: day)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        await cancelPreWorkoutPrime(for: day)
        try? await center.add(request)
    }

    func cancelPreWorkoutPrime(for day: HelmDay) async {
        let identifier = PreWorkoutNotificationPlanner.notificationIdentifier(for: day)
        await center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func postPostWorkoutSummary(
        session: WorkoutSessionDraft,
        personalRecords: [DetectedPersonalRecord]
    ) async {
        await requestPermissionIfNeeded()

        let summary = PostWorkoutSummaryBuilder.build(
            session: session,
            personalRecords: personalRecords
        )

        let content = UNMutableNotificationContent()
        content.title = PostWorkoutNotificationPlanner.title()
        content.body = PostWorkoutNotificationPlanner.body(summary: summary)
        content.sound = .default
        content.categoryIdentifier = PostWorkoutNotificationPlanner.notificationCategoryID
        content.userInfo = [
            PostWorkoutNotificationPlanner.sessionIDUserInfoKey: session.id
        ]

        let identifier = PostWorkoutNotificationPlanner.notificationIdentifier(sessionID: session.id)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        try? await center.add(request)
    }
}
