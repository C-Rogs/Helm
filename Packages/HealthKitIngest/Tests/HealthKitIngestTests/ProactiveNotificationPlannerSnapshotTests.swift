import Core
import Foundation
import HealthKitIngest
import ReadinessKit
import Testing

@Suite("Proactive notification planners")
struct ProactiveNotificationPlannerSnapshotTests {
    @Test("morning brief notification snapshot")
    func morningBriefSnapshot() {
        let brief = StoredDailyBrief(
            helmDay: HelmDay(year: 2026, month: 7, day: 23),
            inputFingerprint: "fp",
            engineText: "ARC 72, primed, high confidence. Today's session: 14 sets across 4 exercises (maintain), emphasis shoulders.",
            narrationText: "ARC 72, primed, high confidence. Today's session: 14 sets across 4 exercises (maintain), emphasis shoulders.",
            citationIDs: [],
            source: .engineOnly,
            promptVersion: nil,
            schemaVersion: nil,
            updatedAt: .now
        )

        let title = BriefNotificationPlanner.title(for: brief)
        let body = BriefNotificationPlanner.body(for: brief)

        #expect(title == morningBriefTitleSnapshot)
        #expect(body == morningBriefBodySnapshot)
    }

    @Test("pre-workout prime notification snapshot")
    func preWorkoutSnapshot() {
        let summary = PrescribedSessionSummary(
            phase: .maintain,
            emphasis: "shoulders",
            exercises: [
                PrescribedExerciseSummary(
                    id: "bench",
                    displayName: "Bench Press",
                    targetSets: 4,
                    targetRepRange: "8-10",
                    targetLoad: "80 kg",
                    targetRPE: "RPE 8"
                ),
                PrescribedExerciseSummary(
                    id: "row",
                    displayName: "Row",
                    targetSets: 3,
                    targetRepRange: "10-12",
                    targetLoad: nil,
                    targetRPE: nil
                )
            ],
            totalSets: 14,
            readinessAdjusted: true
        )

        let title = PreWorkoutNotificationPlanner.title()
        let body = PreWorkoutNotificationPlanner.body(summary: summary, readinessScore: 72)

        #expect(title == preWorkoutTitleSnapshot)
        #expect(body == preWorkoutBodySnapshot)
    }

    @Test("post-workout post-mortem notification snapshot")
    func postWorkoutSnapshot() {
        let summary = PostWorkoutSummary(
            setCount: 16,
            exerciseCount: 5,
            durationMinutes: 62,
            personalRecordCount: 2
        )

        let title = PostWorkoutNotificationPlanner.title()
        let body = PostWorkoutNotificationPlanner.body(summary: summary)

        #expect(title == postWorkoutTitleSnapshot)
        #expect(body == postWorkoutBodySnapshot)
    }

    @Test("notification copy is byte-stable across calls")
    func byteStable() {
        let summary = PostWorkoutSummary(
            setCount: 16,
            exerciseCount: 5,
            durationMinutes: 62,
            personalRecordCount: 2
        )
        let first = PostWorkoutNotificationPlanner.body(summary: summary)
        let second = PostWorkoutNotificationPlanner.body(summary: summary)
        #expect(first == second)
        #expect(first.utf8.elementsEqual(second.utf8))
    }
}

private let morningBriefTitleSnapshot = "Morning brief"

private let morningBriefBodySnapshot = """
ARC 72, primed, high confidence. Today's session: 14 sets across 4 exercises (maintain), emphasis shoulders.
"""

private let preWorkoutTitleSnapshot = "Pre-workout prime"

private let preWorkoutBodySnapshot = "14 sets · 2 exercises · volume trimmed for readiness · ARC 72 · shoulders"

private let postWorkoutTitleSnapshot = "Session complete"

private let postWorkoutBodySnapshot = "16 sets across 5 exercises in 62 min. 2 new PRs."
