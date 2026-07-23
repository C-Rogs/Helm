import Core
import Foundation
import HealthKitIngest
import ReadinessKit
import Testing

@Suite("Planned session window")
struct PlannedSessionWindowEstimatorTests {
    @Test("uses median start time for matching weekday")
    func medianWeekdayStart() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = HelmDay(year: 2026, month: 7, day: 23) // Thursday

        let sessions = [
            session(at: date(2026, 7, 16, 18, 0, calendar: calendar), calendar: calendar),
            session(at: date(2026, 7, 9, 17, 30, calendar: calendar), calendar: calendar),
            session(at: date(2026, 7, 2, 17, 0, calendar: calendar), calendar: calendar)
        ]

        let planned = PlannedSessionWindowEstimator.plannedStart(
            for: day,
            recentSessions: sessions,
            calendar: calendar
        )

        let components = calendar.dateComponents([.hour, .minute], from: try #require(planned))
        #expect(components.hour == 17)
        #expect(components.minute == 30)
    }

    @Test("falls back to default time without history")
    func defaultStartWithoutHistory() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = HelmDay(year: 2026, month: 7, day: 23)

        let planned = PlannedSessionWindowEstimator.plannedStart(
            for: day,
            recentSessions: [],
            calendar: calendar
        )

        let components = calendar.dateComponents([.hour, .minute], from: try #require(planned))
        #expect(components.hour == PlannedSessionWindowEstimator.defaultHour)
        #expect(components.minute == PlannedSessionWindowEstimator.defaultMinute)
    }

    @Test("pre-workout lead time is thirty minutes before planned start")
    func preWorkoutLead() {
        let calendar = Calendar(identifier: .gregorian)
        let plannedStart = date(2026, 7, 23, 18, 0, calendar: calendar)
        let fireDate = PlannedSessionWindowEstimator.preWorkoutFireDate(plannedStart: plannedStart)
        let components = calendar.dateComponents([.hour, .minute], from: fireDate)
        #expect(components.hour == 17)
        #expect(components.minute == 30)
    }

    @Test("skips scheduling when workout already completed today")
    func skipsWhenWorkoutCompleted() {
        let now = date(2026, 7, 23, 16, 0, calendar: Calendar(identifier: .gregorian))
        let fireDate = date(2026, 7, 23, 17, 30, calendar: Calendar(identifier: .gregorian))
        #expect(
            PlannedSessionWindowEstimator.shouldSchedulePreWorkout(
                fireDate: fireDate,
                now: now,
                workoutCompletedToday: true
            ) == false
        )
    }

    private func session(at date: Date, calendar: Calendar) -> WorkoutSessionSummary {
        WorkoutSessionSummary(
            id: UUID().uuidString,
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            totalVolumeKilograms: 1_000,
            totalSetCount: 12,
            totalRepCount: 80,
            exerciseCount: 4
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

@Suite("Threshold insight engine")
struct ThresholdInsightEngineTests {
    @Test("detects contributor crossing above threshold")
    func crossingAbove() {
        let previous = score(hrv: 0.2)
        let current = score(hrv: 1.1)

        let insight = ThresholdInsightEngine.detect(previous: previous, current: current)

        #expect(insight?.id == "hrv_above")
        #expect(insight?.metricLabel == "HRV")
        #expect(insight?.direction == .above)
    }

    @Test("detects contributor crossing below threshold")
    func crossingBelow() {
        let previous = score(hrv: -0.1, sleep: 0.0)
        let current = score(hrv: 0.1, sleep: -1.0)

        let insight = ThresholdInsightEngine.detect(previous: previous, current: current)

        #expect(insight?.id == "sleep_below")
        #expect(insight?.metricLabel == "Sleep")
    }

    @Test("returns nil when no crossing")
    func noCrossing() {
        let previous = score(hrv: 0.2)
        let current = score(hrv: 0.4)
        #expect(ThresholdInsightEngine.detect(previous: previous, current: current) == nil)
    }

    private func score(
        hrv: Double? = nil,
        sleep: Double? = nil
    ) -> ReadinessScore {
        ReadinessScore(
            score: 60,
            band: .balanced,
            confidence: .medium,
            confidenceValue: 0.6,
            hrvBand: .typical,
            validNights: 18,
            stabilityScore: 0.8,
            contributors: ReadinessContributorBreakdown(
                zHRV: hrv,
                zRestingHR: 0.0,
                zSleep: sleep,
                zRespiratory: nil,
                zTemperature: nil,
                zStrain: nil,
                zComposite: 0.1,
                rawScore: 58,
                dampedScore: 60
            ),
            effectiveHRVMilliseconds: 50,
            restingHeartRate: 52
        )
    }
}

@Suite("Post-workout summary builder")
struct PostWorkoutSummaryBuilderTests {
    @Test("counts working sets and duration")
    func summaryCounts() {
        let started = Date(timeIntervalSince1970: 0)
        let ended = started.addingTimeInterval(3_720)
        let session = WorkoutSessionDraft(
            startedAt: started,
            endedAt: ended,
            exercises: [
                WorkoutSessionExerciseDraft(
                    exerciseID: "squat",
                    displayOrder: 0,
                    exerciseMode: .weightReps,
                    sets: [
                        SetEntryDraft(setIndex: 0, setType: .warmup, status: .completed, reps: 10),
                        SetEntryDraft(setIndex: 1, setType: .normal, status: .completed, reps: 8),
                        SetEntryDraft(setIndex: 2, setType: .normal, status: .completed, reps: 8)
                    ]
                )
            ]
        )

        let summary = PostWorkoutSummaryBuilder.build(session: session, personalRecords: [])
        #expect(summary.setCount == 2)
        #expect(summary.exerciseCount == 1)
        #expect(summary.durationMinutes == 62)
        #expect(summary.personalRecordCount == 0)
    }
}
