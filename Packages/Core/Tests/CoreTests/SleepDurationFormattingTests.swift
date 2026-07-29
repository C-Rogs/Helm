import Core
import Testing

@Suite("Sleep duration formatting")
struct SleepDurationFormattingTests {
    @Test("formats hours and minutes")
    func formatsHoursAndMinutes() {
        #expect(SleepDurationFormatting.hoursAndMinutes(from: 7.833) == "7h 50m")
        #expect(SleepDurationFormatting.hoursAndMinutes(from: 5.55) == "5h 33m")
        #expect(SleepDurationFormatting.hoursAndMinutes(from: 0.5) == "30m")
    }
}
