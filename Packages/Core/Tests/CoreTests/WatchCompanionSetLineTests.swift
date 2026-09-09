import Foundation
import Testing
@testable import Core

@Suite("WatchCompanionSetLine")
struct WatchCompanionSetLineTests {
    @Test("formats set, kilograms, and rpe")
    func fullLine() {
        #expect(
            WatchCompanionSetLine.make(
                setNumber: 2,
                setCount: 4,
                targetSummary: "3×8 · 80kg · RPE 8"
            ) == "Set 2/4 . 80 KG . rpe 8"
        )
    }

    @Test("keeps fractional load and RPE")
    func fractional() {
        #expect(
            WatchCompanionSetLine.make(
                setNumber: 1,
                setCount: 3,
                targetSummary: "3×8-10 · 82.5kg · RPE 8.5"
            ) == "Set 1/3 . 82.5 KG . rpe 8.5"
        )
    }

    @Test("omits missing mass or RPE")
    func partial() {
        #expect(
            WatchCompanionSetLine.make(
                setNumber: 1,
                setCount: 2,
                targetSummary: "3×12 · RPE 7"
            ) == "Set 1/2 . rpe 7"
        )
        #expect(
            WatchCompanionSetLine.make(
                setNumber: 3,
                setCount: 3,
                targetSummary: "3×5 · 100kg"
            ) == "Set 3/3 . 100 KG"
        )
    }

    @Test("tokens mark numbers as values")
    func valueTokens() {
        let tokens = WatchCompanionSetLine.tokens(
            setNumber: 2,
            setCount: 4,
            targetSummary: "3×8 · 80kg · RPE 8"
        )
        #expect(tokens.map(\.text) == ["Set ", "2/4", " . ", "80", " KG", " . ", "rpe ", "8"])
        #expect(tokens.map(\.isValue) == [false, true, false, true, false, false, false, true])
    }

    @Test("logged set values override prescription targets")
    func loggedSetValues() {
        let summary = WatchCompanionSetLine.targetSummary(
            massKilograms: 82.5,
            rpe: 8.5,
            fallback: "3×8 · 80kg · RPE 8"
        )
        #expect(summary == "82.5kg · RPE 8.5")
        #expect(
            WatchCompanionSetLine.make(
                setNumber: 2,
                setCount: 3,
                targetSummary: summary
            ) == "Set 2/3 . 82.5 KG . rpe 8.5"
        )
    }

    @Test("missing set value falls back independently")
    func partialLoggedSetValues() {
        #expect(
            WatchCompanionSetLine.targetSummary(
                massKilograms: 85,
                rpe: nil,
                fallback: "3×8 · 80kg · RPE 8"
            ) == "85kg · RPE 8"
        )
    }
}
