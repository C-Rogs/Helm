import Core
import Testing

@Suite("Set type logger cycle")
struct SetTypeLoggerCycleTests {
    @Test("cycles through logger set types")
    func cyclesLoggerSetTypes() {
        #expect(SetType.normal.cycledForLogger() == .warmup)
        #expect(SetType.warmup.cycledForLogger() == .dropSet)
        #expect(SetType.dropSet.cycledForLogger() == .failure)
        #expect(SetType.failure.cycledForLogger() == .normal)
    }

    @Test("logger abbreviations match set types")
    func loggerAbbreviations() {
        #expect(SetType.normal.loggerAbbreviation == nil)
        #expect(SetType.warmup.loggerAbbreviation == "W")
        #expect(SetType.dropSet.loggerAbbreviation == "D")
        #expect(SetType.failure.loggerAbbreviation == "F")
    }

    @Test("logger glyph falls back to set number for normal sets")
    func loggerGlyph() {
        #expect(SetType.normal.loggerGlyph(setNumber: 2) == "2")
        #expect(SetType.warmup.loggerGlyph(setNumber: 1) == "W")
        #expect(SetType.dropSet.loggerGlyph(setNumber: 3) == "D")
        #expect(SetType.failure.loggerGlyph(setNumber: 4) == "F")
    }

    @Test("logger set-type VoiceOver includes set number and type")
    func loggerSetTypeAccessibilityLabel() {
        #expect(
            SetType.normal.loggerSetTypeAccessibilityLabel(setNumber: 3)
                == "Set 3, working set. Tap to change set type."
        )
        #expect(
            SetType.warmup.loggerSetTypeAccessibilityLabel(setNumber: 1)
                == "Set 1, warmup set. Tap to change set type."
        )
        #expect(
            SetType.dropSet.loggerSetTypeAccessibilityLabel(setNumber: 2)
                == "Set 2, drop set. Tap to change set type."
        )
        #expect(
            SetType.failure.loggerSetTypeAccessibilityLabel(setNumber: 4)
                == "Set 4, failure set. Tap to change set type."
        )
    }
}
