import Testing
@testable import PlanKit

@Suite("Scheduled volume forecast")
struct ScheduledVolumeForecastTests {
    @Test("empty upcoming yields no scheduled")
    func emptyUpcomingYieldsNoScheduled() {
        let scheduled = ScheduledVolumeForecast.scheduledSets(
            weeklyTargets: [.chest: 14],
            loggedSets: [.chest: 6],
            upcomingTargetMuscles: []
        )
        #expect(scheduled.isEmpty)
    }

    @Test("splits remaining across upcoming sessions")
    func splitsRemainingAcrossUpcomingSessions() {
        let scheduled = ScheduledVolumeForecast.scheduledSets(
            weeklyTargets: [.chest: 14],
            loggedSets: [.chest: 6],
            upcomingTargetMuscles: [
                [.chest],
                [.chest]
            ]
        )
        // remaining 8 across 2 sessions → 4 + 4
        #expect(scheduled[.chest] == 8)
    }

    @Test("minimum one set when target already met")
    func minimumOneSetWhenTargetAlreadyMet() {
        let scheduled = ScheduledVolumeForecast.scheduledSets(
            weeklyTargets: [.chest: 10],
            loggedSets: [.chest: 12],
            upcomingTargetMuscles: [[.chest]]
        )
        #expect(scheduled[.chest] == 1)
    }

    @Test("projects over MRV risk when sessions stack")
    func projectsOverMRVRiskWhenSessionsStack() {
        let scheduled = ScheduledVolumeForecast.scheduledSets(
            weeklyTargets: [.back: 12],
            loggedSets: [.back: 10],
            upcomingTargetMuscles: [
                [.back],
                [.back],
                [.back]
            ]
        )
        // remaining 2 / 3 → ceil = 1 per session → 3 scheduled; projected 13
        #expect(scheduled[.back] == 3)
    }

    @Test("ignores muscles not on upcoming days")
    func ignoresMusclesNotOnUpcomingDays() {
        let scheduled = ScheduledVolumeForecast.scheduledSets(
            weeklyTargets: [.chest: 14, .quads: 16],
            loggedSets: [.chest: 4, .quads: 8],
            upcomingTargetMuscles: [[.chest]]
        )
        #expect(scheduled[.chest] == 10)
        #expect(scheduled[.quads] == nil)
    }

    @Test("skips muscles without weekly target")
    func skipsMusclesWithoutWeeklyTarget() {
        let scheduled = ScheduledVolumeForecast.scheduledSets(
            weeklyTargets: [.chest: 14],
            loggedSets: [:],
            upcomingTargetMuscles: [[.chest, .calves]]
        )
        #expect(scheduled[.chest] == 14)
        #expect(scheduled[.calves] == nil)
    }

    @Test("skips zero weekly target")
    func skipsZeroWeeklyTarget() {
        let scheduled = ScheduledVolumeForecast.scheduledSets(
            weeklyTargets: [.chest: 0],
            loggedSets: [:],
            upcomingTargetMuscles: [[.chest]]
        )
        #expect(scheduled.isEmpty)
    }
}
