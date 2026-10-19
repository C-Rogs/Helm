import Core
import Foundation
@testable import ReadinessKit
import Testing

@Suite("Illness early warning")
struct IllnessEarlyWarningTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  @Test("no warning with healthy recent vs baseline")
  func healthyNoWarning() {
    let day = HelmDay(year: 2026, month: 7, day: 30)
    let history = makeHistory(
      endingAt: day,
      nights: 35,
      hrv: 50,
      rhr: 52,
      resp: 14,
      temp: 0.0
    )
    let warning = IllnessEarlyWarningDetector.detect(history: history, day: day, calendar: calendar)
    #expect(warning == nil)
  }

  @Test("insufficient baseline nights yields nil")
  func insufficientBaseline() {
    let day = HelmDay(year: 2026, month: 7, day: 10)
    let history = makeHistory(
      endingAt: day,
      nights: 10,
      hrv: 50,
      rhr: 52,
      resp: 14,
      temp: 0.0
    )
    // Force recent anomalies without enough baseline coverage.
    var mutated = history
    if mutated.count >= 2 {
      let last = mutated.count - 1
      mutated[last] = dayInput(
        day: mutated[last].helmDay,
        hrv: 30,
        rhr: 62,
        resp: 16,
        temp: 0.8
      )
      mutated[last - 1] = dayInput(
        day: mutated[last - 1].helmDay,
        hrv: 30,
        rhr: 62,
        resp: 16,
        temp: 0.8
      )
    }
    let warning = IllnessEarlyWarningDetector.detect(history: mutated, day: day, calendar: calendar)
    #expect(warning == nil)
  }

  @Test("single anomaly does not fire")
  func singleAnomalyNoFire() {
    let day = HelmDay(year: 2026, month: 7, day: 30)
    var history = makeHistory(
      endingAt: day,
      nights: 35,
      hrv: 50,
      rhr: 52,
      resp: 14,
      temp: 0.0
    )
    // Only RHR elevated on recent days.
    let last = history.count - 1
    history[last] = dayInput(day: history[last].helmDay, hrv: 50, rhr: 60, resp: 14, temp: 0.0)
    history[last - 1] = dayInput(day: history[last - 1].helmDay, hrv: 50, rhr: 60, resp: 14, temp: 0.0)

    let warning = IllnessEarlyWarningDetector.detect(history: history, day: day, calendar: calendar)
    #expect(warning == nil)
  }

  @Test("two anomalies fire warning")
  func twoAnomaliesFire() {
    let day = HelmDay(year: 2026, month: 7, day: 30)
    var history = makeHistory(
      endingAt: day,
      nights: 35,
      hrv: 50,
      rhr: 52,
      resp: 14,
      temp: 0.0
    )
    let last = history.count - 1
    history[last] = dayInput(day: history[last].helmDay, hrv: 35, rhr: 60, resp: 14, temp: 0.0)
    history[last - 1] = dayInput(day: history[last - 1].helmDay, hrv: 35, rhr: 60, resp: 14, temp: 0.0)

    let warning = IllnessEarlyWarningDetector.detect(history: history, day: day, calendar: calendar)
    #expect(warning != nil)
    #expect(warning?.signals.contains(.hrv) == true)
    #expect(warning?.signals.contains(.restingHeartRate) == true)
    #expect(warning?.message.contains("not a diagnosis") == true)
  }

  @Test("three anomalies include temperature")
  func threeAnomaliesIncludeTemp() {
    let day = HelmDay(year: 2026, month: 7, day: 30)
    var history = makeHistory(
      endingAt: day,
      nights: 35,
      hrv: 50,
      rhr: 52,
      resp: 14,
      temp: 0.0
    )
    let last = history.count - 1
    history[last] = dayInput(day: history[last].helmDay, hrv: 35, rhr: 60, resp: 14, temp: 0.8)
    history[last - 1] = dayInput(day: history[last - 1].helmDay, hrv: 35, rhr: 60, resp: 14, temp: 0.8)

    let warning = IllnessEarlyWarningDetector.detect(history: history, day: day, calendar: calendar)
    #expect(warning?.signals.count ?? 0 >= 3)
    #expect(warning?.signals.contains(.wristTemperature) == true)
  }

  private func makeHistory(
    endingAt day: HelmDay,
    nights: Int,
    hrv: Double,
    rhr: Int,
    resp: Double,
    temp: Double
  ) -> [ReadinessDayInput] {
    (0..<nights).map { offset in
      let helmDay = day.adding(days: offset - (nights - 1), calendar: calendar)
      return dayInput(day: helmDay, hrv: hrv, rhr: rhr, resp: resp, temp: temp)
    }
  }

  private func dayInput(
    day: HelmDay,
    hrv: Double,
    rhr: Int,
    resp: Double,
    temp: Double
  ) -> ReadinessDayInput {
    ReadinessDayInput(
      helmDay: day,
      hrvSleepSDNN: DurationMs(milliseconds: Int(hrv.rounded())),
      restingHeartRate: rhr,
      sleepDurationHours: 7.5,
      sleepEfficiency: 0.9,
      respiratoryRate: resp,
      wristTemperatureDeltaCelsius: temp
    )
  }
}
