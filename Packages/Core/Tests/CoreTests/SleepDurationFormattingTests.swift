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

    @Test("formats whole hours without minutes")
    func formatsWholeHours() {
        #expect(SleepDurationFormatting.hoursAndMinutes(from: 8.0) == "8h")
    }

    @Test("formats sub-hour durations as minutes only")
    func formatsMinutesOnly() {
        #expect(SleepDurationFormatting.hoursAndMinutes(from: 0.016) == "1m")
    }

    @Test("clamps negative durations to zero minutes")
    func clampsNegativeDurations() {
        #expect(SleepDurationFormatting.hoursAndMinutes(from: -1.5) == "0m")
    }

    @Test("rounds to nearest minute")
    func roundsToNearestMinute() {
        #expect(SleepDurationFormatting.hoursAndMinutes(from: 5.549) == "5h 33m")
        #expect(SleepDurationFormatting.hoursAndMinutes(from: 5.551) == "5h 33m")
    }
}
