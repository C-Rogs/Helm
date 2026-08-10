import Testing
@testable import Core

@Suite("Workout Live Activity policy")
struct WorkoutLiveActivityPolicyTests {
    @Test("baseline relevance score")
    func baselineRelevance() {
        #expect(WorkoutLiveActivityPolicy.relevanceScore(elevated: false) == 75)
    }

    @Test("elevated relevance score")
    func elevatedRelevance() {
        #expect(WorkoutLiveActivityPolicy.relevanceScore(elevated: true) == 100)
    }
}
