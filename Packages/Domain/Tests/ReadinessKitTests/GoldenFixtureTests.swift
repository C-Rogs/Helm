import Core
import Foundation
@testable import ReadinessKit
import Testing

@Suite("Golden fixtures")
struct GoldenFixtureTests {
  struct Fixture: Decodable {
    struct Day: Decodable {
      let helmDay: String
      let hrvSleepSDNN: Int?
      let hrvMorningSDNN: Int?
      let hrvDailyAverage: Int?
      let restingHeartRate: Int?
      let sleepDurationHours: Double?
      let sleepEfficiency: Double?
      let deepSleepMinutes: Double?
      let remSleepMinutes: Double?
      let respiratoryRate: Double?
      let wristTemperatureDeltaCelsius: Double?
      let priorDayTRIMP: Double?
    }

    struct Expectation: Decodable {
      let score: Int?
      let scoreTolerance: Double?
      let validNights: Int?
      let confidence: String?
      let nilScore: Bool?
    }

    let referenceDay: String
    let history: [Day]
    let expected: Expectation
  }

  private func helmDay(_ value: String) -> HelmDay {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    return HelmDay(year: parts[0], month: parts[1], day: parts[2])
  }

  private func mapHistory(_ days: [Fixture.Day]) -> [ReadinessDayInput] {
    days.map { day in
      ReadinessDayInput(
        helmDay: helmDay(day.helmDay),
        hrvSleepSDNN: day.hrvSleepSDNN.map(DurationMs.init(milliseconds:)),
        hrvMorningSDNN: day.hrvMorningSDNN.map(DurationMs.init(milliseconds:)),
        hrvDailyAverage: day.hrvDailyAverage.map(DurationMs.init(milliseconds:)),
        restingHeartRate: day.restingHeartRate,
        sleepDurationHours: day.sleepDurationHours,
        sleepEfficiency: day.sleepEfficiency,
        deepSleepMinutes: day.deepSleepMinutes,
        remSleepMinutes: day.remSleepMinutes,
        respiratoryRate: day.respiratoryRate,
        wristTemperatureDeltaCelsius: day.wristTemperatureDeltaCelsius,
        priorDayTRIMP: day.priorDayTRIMP
      )
    }
  }

  private func loadFixture(named name: String) throws -> Fixture {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Fixture.self, from: data)
  }

  @Test("steady baseline synthetic series", arguments: ["steady_baseline", "cold_start", "high_strain_day"])
  func golden(name: String) throws {
    let fixture = try loadFixture(named: name)
    let history = mapHistory(fixture.history)
    let day = helmDay(fixture.referenceDay)
    let score = ReadinessKit.readiness(for: day, history: history)

    if fixture.expected.nilScore == true {
      #expect(score == nil)
    } else {
      #expect(score != nil)
    }

    if let expectedScore = fixture.expected.score, let score {
      let tolerance = fixture.expected.scoreTolerance ?? 2
      #expect(abs(Double(score.score) - Double(expectedScore)) <= tolerance)
    }

    if let validNights = fixture.expected.validNights {
      #expect(ReadinessKit.validNightCount(in: history, through: day) == validNights)
    }

    if let confidence = fixture.expected.confidence, let score {
      #expect(score.confidence.rawValue == confidence)
    }
  }
}
