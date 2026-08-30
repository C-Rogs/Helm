import Foundation
import Testing
@testable import Core

@Suite("Plan builder discussion interpreter")
struct PlanBuilderDiscussionInterpreterTests {
    @Test("parses upper lower and four days")
    func upperLowerFourDays() {
        let parsed = PlanBuilderDiscussionInterpreter.interpret(
            "Can I do a 4 day upper/lower instead?"
        )
        #expect(parsed.daysPerWeek == 4)
        #expect(parsed.preferredTemplateRaw == "upper_lower")
    }

    @Test("parses ppl and full body")
    func templates() {
        #expect(PlanBuilderDiscussionInterpreter.interpret("classic PPL").preferredTemplateRaw == "ppl")
        #expect(PlanBuilderDiscussionInterpreter.interpret("full body please").preferredTemplateRaw == "full_body")
    }

    @Test("applies days onto interview")
    func appliesDays() {
        let interview = PlanBuilderInterview(daysPerWeek: 3, discussionNote: "six day split")
        let next = PlanBuilderDiscussionInterpreter.applying(interview.discussionNote, to: interview)
        #expect(next.daysPerWeek == 6)
    }
}
