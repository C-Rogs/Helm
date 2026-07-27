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
}
