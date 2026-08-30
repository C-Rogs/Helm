import CoachLLM
import Core
import Foundation
import Testing

@Suite("ContextBuilder")
struct ContextBuilderTests {
    private let profile = MemoryProfile(
        baselinesSummary: "HRV chronic ~52 ms, RHR ~51 bpm.",
        mesocyclePosition: "Week 3 accumulating.",
        phaseGoal: PhaseGoal(phase: .gain, weeklyRateKg: 0.25, emphasis: "v-taper"),
        preferences: "Prefer barbell compounds.",
        standingConstraints: "No overhead pressing.",
        whatHasWorked: "RIR 2 on compounds."
    )

    private let evidence = [
        EvidenceRecord(
            id: "ev-squat-depth",
            title: "Squat depth and hypertrophy",
            summary: "Full ROM outperforms partials for quad growth.",
            citation: "Placeholder study",
            placeholder: true
        ),
        EvidenceRecord(
            id: "ev-volume-landmarks",
            title: "Volume landmarks",
            summary: "MEV to MRV framing for weekly hard sets.",
            citation: "Placeholder review",
            placeholder: true
        )
    ]

    private let baselines = """
    hrvChronicMs=52.1
    restingHR=51
    seededNights=28
    """

    private func day(_ formatted: String, text: String) -> CoachContextDay {
        let parts = formatted.split(separator: "-").map(String.init)
        let helmDay = HelmDay(
            year: Int(parts[0]) ?? 0,
            month: Int(parts[1]) ?? 0,
            day: Int(parts[2]) ?? 0
        )
        return CoachContextDay(helmDay: helmDay, text: text)
    }

    private func fixtureDays() -> CoachContextDays {
        CoachContextDays(
            readinessBaselines: baselines,
            evidence: evidence,
            recent: [
                day("2026-07-19", text: "readiness=58 hrv=49ms rhr=52 sleep=6.8h trimp=42"),
                day("2026-07-20", text: "readiness=61 hrv=51ms rhr=51 sleep=7.1h trimp=35"),
                day("2026-07-21", text: "readiness=64 hrv=53ms rhr=50 sleep=7.4h trimp=28")
            ]
        )
    }

    @Test("training plan snapshot is included in stable prefix")
    func trainingPlanSnapshotInPrefix() {
        let days = CoachContextDays(
            readinessBaselines: baselines,
            evidence: evidence,
            recent: fixtureDays().recent,
            trainingPlanSnapshot: """
            engine_note=split_rotation_only
            emphasis="calves"
            today_split=Push
            rolling_7d_hard_sets:
              calves: 2 hard sets | MEV 6 MRV 14
            """
        )

        let prefix = ContextBuilder.stablePrefixText(profile: profile, days: days)
        #expect(prefix.contains("# Training Plan Snapshot"))
        #expect(prefix.contains("emphasis=\"calves\""))
    }

    @Test("follow-up keeps training plan snapshot")
    func followUpKeepsTrainingPlanSnapshot() {
        let days = CoachContextDays(
            trainingPlanSnapshot: "emphasis=\"agility\"",
            weekAheadSchedule: "- 2026-07-28: Rest busy=Busy day"
        )
        let prompt = ContextBuilder.build(
            profile: profile,
            days: days,
            budget: 48_000,
            turn: .followUp
        )
        #expect(prompt.contextBlock.contains("emphasis=\"agility\""))
        #expect(prompt.contextBlock.contains("# Week Ahead Schedule"))
        #expect(prompt.contextBlock.contains("busy=Busy day"))
    }

    @Test("follow-up includes standing constraints")
    func followUpIncludesStandingConstraints() {
        let prompt = ContextBuilder.build(
            profile: profile,
            days: fixtureDays(),
            budget: 48_000,
            turn: .followUp
        )
        #expect(prompt.contextBlock.contains("# Standing Constraints"))
        #expect(prompt.contextBlock.contains("No overhead pressing."))
    }

    @Test("prefix ordering is byte-stable across calls")
    func prefixByteStable() {
        let days = fixtureDays()
        let first = ContextBuilder.stablePrefixText(profile: profile, days: days)
        let second = ContextBuilder.stablePrefixText(profile: profile, days: days)

        #expect(first == second)
        #expect(first.utf8.elementsEqual(second.utf8))
        #expect(first.hasPrefix("# Memory Profile\n## Baselines\nHRV chronic ~52 ms"))
        #expect(first.contains("# Readiness Baselines\nhrvChronicMs=52.1"))
        #expect(first.contains("# Evidence Index\n- [ev-squat-depth]"))
        #expect(first.contains("- [ev-volume-landmarks]"))
    }

    @Test("snapshot over fixed inputs")
    func snapshotFixedInputs() {
        let prompt = ContextBuilder.build(
            profile: profile,
            days: fixtureDays(),
            budget: 10_000,
            turn: .initial
        )

        #expect(prompt.systemInstructions == CoachSystemPrompt.chatV1)
        #expect(prompt.includedDayCount == 3)
        #expect(prompt.droppedDayCount == 0)
        #expect(prompt.contextBlock.hasPrefix("# Memory Profile\n## Baselines\nHRV chronic ~52 ms"))
        #expect(prompt.contextBlock.contains("# Recent Days"))
        #expect(prompt.contextBlock.contains("## 2026-07-19\nreadiness=58"))
        #expect(prompt.contextBlock.contains("## 2026-07-21\nreadiness=64"))
        #expect(prompt.estimatedTokens > 0)
    }

    @Test("trimming drops oldest days first")
    func trimmingDropsOldestFirst() {
        let days = fixtureDays()
        let prefix = ContextBuilder.stablePrefixText(profile: profile, days: days)
        let allDays = ContextBuilder.build(
            profile: profile,
            days: days,
            budget: 10_000,
            turn: .initial
        )
        let oneDay = ContextBuilder.build(
            profile: profile,
            days: CoachContextDays(
                readinessBaselines: baselines,
                evidence: evidence,
                recent: [day("2026-07-21", text: "readiness=64 hrv=53ms rhr=50 sleep=7.4h trimp=28")]
            ),
            budget: 10_000,
            turn: .initial
        )

        let tightBudget = max(
            TokenBudget.estimateTokens(characterCount: prefix.count) + 1,
            TokenBudget.estimateTokens(characterCount: oneDay.contextBlock.count)
        )

        let prompt = ContextBuilder.build(
            profile: profile,
            days: days,
            budget: tightBudget,
            turn: .initial
        )

        #expect(prompt.includedDayCount < 3)
        #expect(prompt.droppedDayCount > 0)
        #expect(prompt.contextBlock.contains("# Memory Profile"))
        #expect(prompt.contextBlock.contains("# Readiness Baselines"))
        #expect(prompt.contextBlock.contains("# Evidence Index"))
        #expect(!prompt.contextBlock.contains("## 2026-07-19"))
        #expect(prompt.contextBlock.contains("## 2026-07-21"))
        #expect(
            TokenBudget.estimateTokens(characterCount: prompt.contextBlock.count) <= tightBudget
        )
        _ = allDays
    }

    @Test("trimming never splits the stable prefix")
    func trimmingNeverSplitsPrefix() {
        let prompt = ContextBuilder.build(
            profile: profile,
            days: fixtureDays(),
            budget: 1,
            turn: .initial
        )

        let expectedPrefix = ContextBuilder.stablePrefixText(profile: profile, days: fixtureDays())
        #expect(prompt.contextBlock == expectedPrefix)
        #expect(prompt.includedDayCount == 0)
        #expect(prompt.droppedDayCount == 3)
        #expect(!prompt.contextBlock.contains("# Recent Days"))
    }

    @Test("follow-up keeps today recovery and baselines without full recent days")
    func followUpKeepsTodayAndBaselines() {
        let workouts = """
        Push Day

        Bench Press
        100kg x 5
        """
        let days = CoachContextDays(
            readinessBaselines: baselines,
            evidence: evidence,
            recent: [
                day("2026-07-19", text: "readiness=58 hrv=49ms rhr=52 sleep=6.8h trimp=42"),
                day("2026-07-20", text: "readiness=61 hrv=51ms rhr=51 sleep=7.1h trimp=35")
            ],
            recentWorkouts: workouts
        )

        let prompt = ContextBuilder.build(
            profile: profile,
            days: days,
            budget: 10_000,
            turn: .followUp
        )

        #expect(prompt.contextBlock.contains("# Recent Workouts"))
        #expect(prompt.contextBlock.contains("Bench Press"))
        #expect(prompt.contextBlock.contains("# Phase"))
        #expect(prompt.contextBlock.contains("# Readiness Baselines"))
        #expect(prompt.contextBlock.contains("hrvChronicMs=52.1"))
        #expect(prompt.contextBlock.contains("# Today"))
        #expect(prompt.contextBlock.contains("## 2026-07-20"))
        #expect(prompt.contextBlock.contains("readiness=61"))
        #expect(prompt.includedDayCount == 0)
        #expect(prompt.droppedDayCount == 2)
        #expect(!prompt.contextBlock.contains("# Memory Profile"))
        #expect(!prompt.contextBlock.contains("# Recent Days"))
        #expect(!prompt.contextBlock.contains("readiness=58"))
    }

    @Test("follow-up keeps slim phase when workouts missing")
    func followUpKeepsSlimPhaseWithoutWorkouts() {
        let prompt = ContextBuilder.build(
            profile: profile,
            days: fixtureDays(),
            budget: 10_000,
            turn: .followUp
        )

        #expect(prompt.contextBlock.contains("# Phase"))
        #expect(prompt.contextBlock.contains("phase=gain"))
        #expect(prompt.contextBlock.contains("# Today"))
        #expect(prompt.contextBlock.contains("readiness=64"))
        #expect(prompt.includedDayCount == 0)
        #expect(prompt.droppedDayCount == 3)
        #expect(!prompt.contextBlock.contains("# Recent Days"))
        #expect(!prompt.contextBlock.contains("readiness=58"))
    }

    @Test("evidence index sorts by id for stable output")
    func evidenceIndexStableOrder() {
        let shuffled = CoachContextDays(
            readinessBaselines: baselines,
            evidence: evidence.reversed(),
            recent: []
        )

        let text = EvidenceIndex.stableText(from: shuffled.evidence)
        let firstIndex = text.range(of: "ev-squat-depth")?.lowerBound
        let secondIndex = text.range(of: "ev-volume-landmarks")?.lowerBound

        #expect(firstIndex != nil)
        #expect(secondIndex != nil)
        #expect(firstIndex! < secondIndex!)
    }

    @Test("app surface rides on freshness suffix, not stable prefix")
    func appSurfaceOnFreshnessSuffix() {
        let surface = CoachAppSurfaceSnapshot(
            selectedTab: "nutrition",
            sessionStatus: "active",
            sessionTitle: "Push",
            viewedNutritionDay: "2026-08-20"
        )
        let prompt = ContextBuilder.build(
            profile: profile,
            days: fixtureDays(),
            budget: 10_000,
            turn: .initial,
            appSurface: surface
        )

        let suffix = prompt.freshnessSuffix ?? ""
        #expect(suffix.contains("# App State"))
        #expect(suffix.contains("tab=nutrition"))
        #expect(suffix.contains("session=active"))
        #expect(suffix.contains("session_title=Push"))
        #expect(suffix.contains("nutrition_day=2026-08-20"))
        #expect(!prompt.contextBlock.contains("# App State"))
        #expect(prompt.contextBlock.hasPrefix("# Memory Profile"))
    }
}
