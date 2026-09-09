import Core
import Foundation
import Persistence
import Testing

@Suite("Training overview aggregates")
struct TrainingOverviewAggregateTests {
    @Test("fetchTrainingOverviewAggregate counts sessions and volume in window")
    func aggregateWindow() throws {
        let store = try PersistenceStore.inMemory()
        let startedAt = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!

        try store.workoutSessions.insert(
            WorkoutSessionDraft(
                id: "signal-1",
                title: "Push",
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(3_600),
                status: .completed,
                source: .manual,
                exercises: [
                    WorkoutSessionExerciseDraft(
                        id: "wse-1",
                        exerciseID: "exercise-bench",
                        displayOrder: 0,
                        exerciseMode: .weightReps,
                        sets: [
                            SetEntryDraft(
                                id: "set-1",
                                setIndex: 0,
                                mass: Mass(kilograms: 80),
                                reps: 8,
                                completedAt: startedAt
                            )
                        ]
                    )
                ]
            )
        )

        _ = try store.workoutSessions.upsertHealthKitWorkout(
            hkUUID: "HK-RUN-1",
            title: "Run",
            startedAt: startedAt.addingTimeInterval(86_400),
            endedAt: startedAt.addingTimeInterval(86_400 + 1_800),
            activityType: "Running",
            activeEnergyKilocalories: 220,
            distanceMeters: 5_000,
            sourceBundleID: "com.apple.health"
        )

        let startDay = HelmDay(year: 2026, month: 8, day: 6)
        let endDay = HelmDay(year: 2026, month: 8, day: 7)
        let aggregate = try store.workoutSessions.fetchTrainingOverviewAggregate(
            since: startDay,
            through: endDay
        )

        #expect(aggregate.sessionCount == 2)
        #expect(aggregate.helmSessionCount == 1)
        #expect(aggregate.totalSets == 1)
        #expect(aggregate.totalVolumeKg > 0)
    }

    @Test("listSummaries on day returns healthKit and signal workouts")
    func summariesOnDay() throws {
        let store = try PersistenceStore.inMemory()
        let startedAt = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!

        _ = try store.workoutSessions.upsertHealthKitWorkout(
            hkUUID: "HK-CF-1",
            title: "CrossFit",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(2_700),
            activityType: "Cross Training",
            activeEnergyKilocalories: 410,
            distanceMeters: nil,
            sourceBundleID: "com.apple.health"
        )

        let day = HelmDay(year: 2026, month: 8, day: 6)
        let summaries = try store.workoutSessions.listSummaries(on: day)

        #expect(summaries.count == 1)
        #expect(summaries.first?.source == .healthKit)
        #expect(summaries.first?.hkActiveEnergyKilocalories == 410)
    }

    @Test("earliestCompletedSessionDay spans full history for All analytics")
    func earliestSessionDayAndAllRangeAggregate() throws {
        let store = try PersistenceStore.inMemory()
        let oldStart = ISO8601DateFormatter().date(from: "2024-01-15T10:00:00Z")!
        let recentStart = ISO8601DateFormatter().date(from: "2026-08-06T10:00:00Z")!

        try store.workoutSessions.insert(
            WorkoutSessionDraft(
                id: "old-session",
                title: "Legacy",
                startedAt: oldStart,
                endedAt: oldStart.addingTimeInterval(3_600),
                status: .completed,
                source: .manual,
                exercises: []
            )
        )
        try store.workoutSessions.insert(
            WorkoutSessionDraft(
                id: "recent-session",
                title: "Recent",
                startedAt: recentStart,
                endedAt: recentStart.addingTimeInterval(3_600),
                status: .completed,
                source: .manual,
                exercises: []
            )
        )

        let earliest = try #require(try store.workoutSessions.earliestCompletedSessionDay())
        let endDay = HelmDay(year: 2026, month: 8, day: 7)
        #expect(earliest == HelmDay.day(for: oldStart, calendar: .current))

        let aggregate = try store.workoutSessions.fetchTrainingOverviewAggregate(
            since: earliest,
            through: endDay
        )
        #expect(aggregate.sessionCount == 2)
        #expect(earliest.days(to: endDay) > 365)
    }
}
