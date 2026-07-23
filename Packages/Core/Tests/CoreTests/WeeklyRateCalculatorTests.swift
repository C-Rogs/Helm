import Foundation
import Testing
@testable import Core

@Suite("Weekly rate calculator")
struct WeeklyRateCalculatorTests {
    @Test("computes weekly cut rate from target date")
    func cutRate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let result = WeeklyRateCalculator.calculate(
            WeeklyRateCalculator.Input(
                currentWeightKg: 90,
                targetWeightKg: 86,
                targetDate: target,
                referenceDate: reference
            ),
            calendar: calendar
        )
        #expect(result?.phase == .cut)
        #expect(abs((result?.weeklyRateKg ?? 0) - 0.93) < 0.1)
    }
}
