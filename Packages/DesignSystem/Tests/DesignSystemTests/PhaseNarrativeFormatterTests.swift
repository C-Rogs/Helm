import Testing
@testable import DesignSystem

@Suite("Phase narrative formatter")
struct PhaseNarrativeFormatterTests {
    @Test("example journey line")
    func exampleLine() {
        let text = PhaseNarrativeFormatter.string(
            currentWeek: 3,
            mesocyclePhase: "Accumulating",
            goalPhase: "Cut"
        )
        #expect(text == "Week 3 · Hypertrophy · Cut")
    }

    @Test("maps deload and includes signed rate")
    func deloadWithRate() {
        let text = PhaseNarrativeFormatter.string(
            currentWeek: 5,
            blockLengthWeeks: 5,
            includeBlockLength: true,
            mesocyclePhase: "Deload",
            goalPhase: "Cut · abs",
            weeklyRateKg: 0.5
        )
        #expect(text == "Week 5 of 5 · Deload · Cut · −0.5 kg/wk")
    }

    @Test("falls back to experience when mesocycle missing")
    func experienceFallback() {
        let text = PhaseNarrativeFormatter.string(
            currentWeek: 2,
            experienceLabel: "Intermediate",
            goalPhase: "Gain · v-taper",
            weeklyRateKg: 0.5
        )
        #expect(text == "Week 2 · Intermediate · Gain · +0.5 kg/wk")
    }

    @Test("from progression model mid-meso")
    func fromModel() {
        let text = PhaseNarrativeFormatter.string(from: .midMesoFixture)
        #expect(text == "Week 3 · Hypertrophy · Gain")
    }

    @Test("primary goal strips emphasis")
    func primaryGoal() {
        #expect(PhaseNarrativeFormatter.primaryGoalLabel("Gain · v-taper") == "Gain")
        #expect(PhaseNarrativeFormatter.primaryGoalLabel("  Cut  ") == "Cut")
        #expect(PhaseNarrativeFormatter.primaryGoalLabel(nil) == nil)
    }

    @Test("maintain omits rate")
    func maintainOmitsRate() {
        let rate = PhaseNarrativeFormatter.formatWeeklyRate(0.3, goalPhase: "Maintain")
        #expect(rate == nil)
    }
}
