import Testing
@testable import DesignSystem

@Suite("Recomp story classifier")
struct RecompStoryClassifierTests {
    @Test("warm empty when no signals")
    func insufficient() {
        let story = RecompStoryClassifier.classify(RecompStorySignals())
        #expect(story.kind == .insufficient)
        #expect(story.isEmptyState)
        #expect(story.headline.contains("Not enough"))
    }

    @Test("scale flat strength up")
    func recompStrength() {
        let story = RecompStoryClassifier.classify(
            RecompStorySignals(weight: .flat, strength: .rising)
        )
        #expect(story.kind == .recompStrength)
        #expect(story.headline == "Scale flat. Strength is climbing.")
    }

    @Test("scale flat body fat down")
    func recompBodyFat() {
        let story = RecompStoryClassifier.classify(
            RecompStorySignals(weight: .flat, bodyFat: .falling)
        )
        #expect(story.kind == .recompBodyFat)
        #expect(story.headline == "Scale flat. Body fat is trending down.")
    }

    @Test("scale down volume held")
    func fatLossFriendly() {
        let story = RecompStoryClassifier.classify(
            RecompStorySignals(weight: .falling, volume: .flat)
        )
        #expect(story.kind == .fatLossFriendly)
        #expect(story.headline == "Scale is down. Training is holding.")
    }

    @Test("scale up strength up")
    func surplusWorking() {
        let story = RecompStoryClassifier.classify(
            RecompStorySignals(weight: .rising, strength: .rising)
        )
        #expect(story.kind == .surplusWorking)
        #expect(story.headline == "Scale up. Strength is climbing.")
    }

    @Test("signal math flat band")
    func signalMath() {
        #expect(
            RecompSignalMath.direction(newer: 80.1, older: 80.0, flatAbsolute: 0.25) == .flat
        )
        #expect(
            RecompSignalMath.direction(newer: 82.0, older: 80.0, flatAbsolute: 0.25) == .rising
        )
        #expect(
            RecompSignalMath.directionFromSeries([100, 101, 104], flatAbsolute: 1.0) == .rising
        )
        #expect(
            RecompSignalMath.directionFromSeries([100], flatAbsolute: 1.0) == .unknown
        )
    }
}
