import CoachLLM
import Core
import Foundation
import Testing

@Suite("MemoryProfile stable prefix")
struct MemoryProfileTests {
    @Test("stable prefix is byte-stable for identical content")
    func stablePrefixByteStable() {
        let profile = MemoryProfile(
            baselinesSummary: "HRV chronic ~52 ms, RHR ~51 bpm.",
            mesocyclePosition: "Week 3 accumulating, deload next week.",
            phaseGoal: PhaseGoal(phase: .gain, weeklyRateKg: 0.25, emphasis: "v-taper"),
            preferences: "Prefer barbell compounds.\nShort sessions on weekdays.",
            standingConstraints: "No overhead pressing (shoulder).",
            whatHasWorked: "RIR 2 on compounds; 90s rest on accessories."
        )

        let first = profile.stablePrefixText()
        let second = profile.stablePrefixText()

        #expect(first == second)
        #expect(first.utf8.elementsEqual(second.utf8))
    }

    @Test("stable prefix snapshot")
    func stablePrefixSnapshot() {
        let profile = MemoryProfile(
            baselinesSummary: "HRV chronic ~52 ms.",
            mesocyclePosition: "Week 2 accumulating.",
            phaseGoal: PhaseGoal(phase: .maintain, emphasis: "legs"),
            preferences: "Morning training.",
            standingConstraints: "Home gym only.",
            whatHasWorked: "Higher frequency for arms."
        )

        let prefix = profile.stablePrefixText()

        #expect(prefix.hasPrefix("## Baselines\nHRV chronic ~52 ms."))
        #expect(prefix.contains("## Mesocycle\nWeek 2 accumulating."))
        #expect(prefix.contains("phase=maintain"))
        #expect(prefix.contains("emphasis=legs"))
        #expect(prefix.contains("## Preferences\nMorning training."))
        #expect(prefix.contains("## Standing Constraints\nHome gym only."))
        #expect(prefix.contains("## What Has Worked\nHigher frequency for arms."))
    }

    @Test("normalizes line endings in prefix")
    func normalizesLineEndings() {
        let profile = MemoryProfile(preferences: "Line one\r\nLine two\r\nLine three")
        let prefix = profile.stablePrefixText()
        #expect(prefix.contains("Line one\nLine two\nLine three"))
        #expect(!prefix.contains("\r"))
    }

    @Test("decodes legacy JSON missing newer memory fields")
    func decodesLegacyJSON() throws {
        let json = """
        {
          "baselines_summary": "HRV ok",
          "mesocycle_position": "Week 1",
          "preferences": "Barbell",
          "standing_constraints": "Shoulder",
          "what_has_worked": "RIR 2"
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let profile = try decoder.decode(MemoryProfile.self, from: Data(json.utf8))
        #expect(profile.baselinesSummary == "HRV ok")
        #expect(profile.preferences == "Barbell")
        #expect(profile.activeModules.isEmpty)
        #expect(profile.injuryHistory.isEmpty)
        #expect(profile.trainingResponses.isEmpty)
        #expect(profile.nutritionPatterns.isEmpty)
    }
}
