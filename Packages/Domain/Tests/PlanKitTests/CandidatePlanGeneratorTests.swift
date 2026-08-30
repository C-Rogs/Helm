import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Candidate plan generator")
struct CandidatePlanGeneratorTests {
    @Test("deterministic output for identical inputs")
    func deterministic() {
        let interview = PlanBuilderInterview(daysPerWeek: 4, sessionDurationMinutes: 60, progressionGoal: .hypertrophy)
        let a = CandidatePlanGenerator.generate(interview: interview, experience: .intermediate)
        let b = CandidatePlanGenerator.generate(interview: interview, experience: .intermediate)
        #expect(a == b)
    }

    @Test("availability buckets produce distinct candidates")
    func distinctCandidates() {
        for days in 2 ... 6 {
            let interview = PlanBuilderInterview(daysPerWeek: days, sessionDurationMinutes: 60)
            let candidates = CandidatePlanGenerator.generate(interview: interview, experience: .intermediate)
            #expect(candidates.count >= 2)
            #expect(Set(candidates.map(\.id)).count == candidates.count)
            for candidate in candidates {
                #expect(candidate.daysPerWeek >= 2)
                #expect(candidate.weeklyPeakSetsByMuscle.values.allSatisfy { $0 > 0 })
                #expect((0.0 ... 1.0).contains(candidate.availabilityFitScore))
            }
        }
    }

    @Test("strength goal trims peak sets versus hypertrophy")
    func strengthTrimsVolume() {
        let strength = CandidatePlanGenerator.generate(
            interview: PlanBuilderInterview(daysPerWeek: 3, progressionGoal: .strength),
            experience: .intermediate
        )
        let hypertrophy = CandidatePlanGenerator.generate(
            interview: PlanBuilderInterview(daysPerWeek: 3, progressionGoal: .hypertrophy),
            experience: .intermediate
        )

        let strengthChest = strength[0].weeklyPeakSetsByMuscle[.chest] ?? 0
        let hypertrophyChest = hypertrophy[0].weeklyPeakSetsByMuscle[.chest] ?? 0
        #expect(strengthChest < hypertrophyChest)
    }

    @Test("advanced experience scales volume above novice")
    func experienceScalesVolume() {
        let novice = CandidatePlanGenerator.generate(
            interview: PlanBuilderInterview(daysPerWeek: 3),
            experience: .novice
        )
        let advanced = CandidatePlanGenerator.generate(
            interview: PlanBuilderInterview(daysPerWeek: 3),
            experience: .advanced
        )
        let noviceChest = novice[0].weeklyPeakSetsByMuscle[.chest] ?? 0
        let advancedChest = advanced[0].weeklyPeakSetsByMuscle[.chest] ?? 0
        #expect(advancedChest >= noviceChest)
    }

    @Test("upper/lower and full-body blueprints persist matching templates")
    func dedicatedTemplateRaw() {
        let twoDay = CandidatePlanGenerator.generate(
            interview: PlanBuilderInterview(daysPerWeek: 2, sessionDurationMinutes: 60),
            experience: .intermediate
        )
        #expect(twoDay.first { $0.id == "fullbody_2day" }?.programTemplateRaw == "full_body")
        #expect(twoDay.first { $0.id == "upperlower_2day" }?.programTemplateRaw == "upper_lower")

        let threeDay = CandidatePlanGenerator.generate(
            interview: PlanBuilderInterview(daysPerWeek: 3, sessionDurationMinutes: 60),
            experience: .intermediate
        )
        #expect(threeDay.first { $0.id == "ppl_3day" }?.programTemplateRaw == "ppl")
        #expect(threeDay.first { $0.id == "fullbody_3day" }?.programTemplateRaw == "full_body")

        let fourDay = CandidatePlanGenerator.generate(
            interview: PlanBuilderInterview(daysPerWeek: 4, sessionDurationMinutes: 60),
            experience: .intermediate
        )
        #expect(fourDay.first { $0.id == "upperlower_4day" }?.programTemplateRaw == "upper_lower")
    }

    @Test("discussion preferred template is listed first")
    func preferredTemplateFirst() {
        let interview = PlanBuilderInterview(daysPerWeek: 4, sessionDurationMinutes: 60)
        let candidates = CandidatePlanGenerator.generate(
            interview: interview,
            experience: .intermediate,
            preferredTemplateRaw: "upper_lower"
        )
        #expect(candidates.first?.programTemplateRaw == "upper_lower")
    }
}
