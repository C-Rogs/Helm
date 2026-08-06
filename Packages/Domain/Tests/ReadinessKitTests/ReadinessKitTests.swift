import Core
import Foundation
@testable import ReadinessKit
import Testing

@Suite("ReadinessKit engine")
struct ReadinessKitTests {
  private let endDay = HelmDay(year: 2024, month: 1, day: 30)

  private func baselineHistory(
    nights: Int,
    hrvMilliseconds: Int = 50,
    restingHR: Int = 60,
    sleepHours: Double = 7.5
  ) -> [ReadinessDayInput] {
    (-(nights - 1)...0).map { offset in
      ReadinessDayInput(
        helmDay: endDay.adding(days: offset),
        hrvDailyAverage: DurationMs(milliseconds: hrvMilliseconds),
        restingHeartRate: restingHR,
        sleepDurationHours: sleepHours,
        sleepEfficiency: 0.9,
        deepSleepMinutes: 50,
        remSleepMinutes: 90
      )
    }
  }

  @Test("cold start returns nil below four nights")
  func coldStart() {
    let history = baselineHistory(nights: 3)
    let score = ReadinessKit.readiness(for: endDay, history: history)
    #expect(score == nil)
    #expect(ReadinessKit.validNightCount(in: history, through: endDay) == 3)
    #expect(ReadinessKit.buildingBaselineMessage(validNights: 3) == "Building baseline (3/4 nights)")
  }

  @Test("steady baseline maps near 58")
  func baselineAnchor() {
    let history = baselineHistory(nights: 30)
    let score = ReadinessKit.readiness(for: endDay, history: history)
    #expect(score != nil)
    #expect(abs(Double(score!.score) - 58) < 4)
  }

  @Test("positive z injection scores high")
  func positiveInjection() {
    var history = baselineHistory(nights: 29)
    history.append(
      ReadinessDayInput(
        helmDay: endDay,
        hrvDailyAverage: DurationMs(milliseconds: 90),
        restingHeartRate: 52,
        sleepDurationHours: 9,
        sleepEfficiency: 0.95,
        deepSleepMinutes: 80,
        remSleepMinutes: 120
      )
    )
    let score = ReadinessKit.readiness(for: endDay, history: history)
    #expect((score?.score ?? 0) > 70)
  }

  @Test("negative z injection scores low")
  func negativeInjection() {
    var history = baselineHistory(nights: 29, hrvMilliseconds: 55, restingHR: 58)
    history.append(
      ReadinessDayInput(
        helmDay: endDay,
        hrvDailyAverage: DurationMs(milliseconds: 25),
        restingHeartRate: 72,
        sleepDurationHours: 4.5,
        sleepEfficiency: 0.6,
        deepSleepMinutes: 20,
        remSleepMinutes: 40
      )
    )
    let score = ReadinessKit.readiness(for: endDay, history: history)
    #expect((score?.score ?? 100) < 35)
  }

  @Test("logistic squash anchors at baseline")
  func logisticAnchors() {
    #expect(abs(ReadinessKit.logisticSquash(0) - 58) < 2)
    #expect(ReadinessKit.logisticSquash(2) > 90)
    #expect(ReadinessKit.logisticSquash(-2) < 10)
  }

  @Test("missing optional signals redistribute to required terms")
  func optionalRedistribution() {
    let z = ReadinessKit.compositeZ(
      zHRV: 0.5,
      zRHR: 0.2,
      zSleep: 0.1,
      zResp: nil,
      zTemp: nil,
      zStrain: nil
    )
    #expect(z != nil)
    let requiredWeight = 0.42 + 0.18 + 0.22
    let expected = 0.5 * 0.42 / requiredWeight + 0.2 * 0.18 / requiredWeight + 0.1 * 0.22 / requiredWeight
    #expect(abs((z ?? 0) - expected) < 0.01)
  }

  @Test("sleep-window HRV preferred over daily average")
  func sleepWindowHRVPreferred() {
    var history = baselineHistory(nights: 20)
    history.append(
      ReadinessDayInput(
        helmDay: endDay,
        hrvSleepSDNN: DurationMs(milliseconds: 70),
        hrvDailyAverage: DurationMs(milliseconds: 40),
        restingHeartRate: 60,
        sleepDurationHours: 7.5,
        sleepEfficiency: 0.9,
        deepSleepMinutes: 50,
        remSleepMinutes: 90
      )
    )
    let balance = HRVAnalyzer.hrvBalance(
      history: history,
      through: endDay,
      chronicBaseline: nil
    )
    #expect(balance.nightlyHRV.last == 70)
  }

  @Test("provisional damping pulls toward anchor between four and thirteen nights")
  func provisionalDamping() {
    let history = baselineHistory(nights: 10, hrvMilliseconds: 55, restingHR: 58)
    let score = ReadinessKit.readiness(for: endDay, history: history)
    #expect(score != nil)
    let raw = score?.contributors.rawScore
    let damped = score?.contributors.dampedScore
    #expect(raw != nil)
    #expect(damped != nil)
    if let raw, let damped {
      #expect(abs(damped - raw) < abs(damped - 58) + 0.01)
    }
  }

  @Test("high prior-day TRIMP lowers readiness")
  func strainCarryover() {
    var history = baselineHistory(nights: 20)
    for index in history.indices.dropLast() {
      history[index] = ReadinessDayInput(
        helmDay: history[index].helmDay,
        hrvDailyAverage: DurationMs(milliseconds: 50),
        restingHeartRate: 60,
        sleepDurationHours: 7.5,
        sleepEfficiency: 0.9,
        deepSleepMinutes: 50,
        remSleepMinutes: 90,
        priorDayTRIMP: 50
      )
    }
    history[history.count - 1] = ReadinessDayInput(
      helmDay: endDay,
      hrvDailyAverage: DurationMs(milliseconds: 50),
      restingHeartRate: 60,
      sleepDurationHours: 7.5,
      sleepEfficiency: 0.9,
      deepSleepMinutes: 50,
      remSleepMinutes: 90,
      priorDayTRIMP: 200
    )

    let withStrain = ReadinessKit.readiness(for: endDay, history: history)
    let baseline = ReadinessKit.readiness(for: endDay, history: baselineHistory(nights: 20))
    #expect((withStrain?.score ?? 0) < (baseline?.score ?? 100))
  }

  @Test("confidence labels")
  func confidenceLabels() {
    #expect(ReadinessKit.confidenceLabel(for: 0.8) == .high)
    #expect(ReadinessKit.confidenceLabel(for: 0.5) == .medium)
    #expect(ReadinessKit.confidenceLabel(for: 0.2) == .low)
  }

  @Test("seed baselines from backfill history")
  func seedBaselines() {
    let history = baselineHistory(nights: 60)
    let seeded = ReadinessKit.seedBaselines(from: history)
    #expect(seeded.seededNightCount == 60)
    #expect(seeded.hrvChronic != nil)
    #expect(seeded.restingHR != nil)
  }

  @Test("spike in SDNN milliseconds raises HRV z-score")
  func hrvUnitGuard() {
    var history = baselineHistory(nights: 20, hrvMilliseconds: 50)
    history[history.count - 1] = ReadinessDayInput(
      helmDay: endDay,
      hrvDailyAverage: DurationMs(milliseconds: 5_000),
      restingHeartRate: 60,
      sleepDurationHours: 7.5,
      sleepEfficiency: 0.9,
      deepSleepMinutes: 50,
      remSleepMinutes: 90
    )
    let score = ReadinessKit.readiness(for: endDay, history: history)
    #expect(score != nil)
    #expect((score?.contributors.zHRV ?? 0) > 1.0)
  }

    @Test("DurationMs spike scores higher than chronically low SDNN")
    func hrvMillisecondsScale() {
        var healthy = baselineHistory(nights: 19, hrvMilliseconds: 50)
        healthy.append(
      ReadinessDayInput(
        helmDay: endDay,
        hrvDailyAverage: DurationMs(milliseconds: 80),
        restingHeartRate: 60,
        sleepDurationHours: 7.5,
        sleepEfficiency: 0.9,
        deepSleepMinutes: 50,
        remSleepMinutes: 90
      )
    )
    var low = baselineHistory(nights: 19, hrvMilliseconds: 50)
    low.append(
      ReadinessDayInput(
        helmDay: endDay,
        hrvDailyAverage: DurationMs(milliseconds: 15),
        restingHeartRate: 60,
        sleepDurationHours: 7.5,
        sleepEfficiency: 0.9,
        deepSleepMinutes: 50,
        remSleepMinutes: 90
      )
    )
    let healthyScore = ReadinessKit.readiness(for: endDay, history: healthy)?.score
    let lowScore = ReadinessKit.readiness(for: endDay, history: low)?.score
    #expect((healthyScore ?? 0) > (lowScore ?? 100))
  }
}

@Suite("Readiness band hysteresis")
struct ReadinessBandHysteresisTests {
  @Test("no previous band matches legacy thresholds")
  func noPreviousMatchesLegacy() {
    #expect(ReadinessBand.classify(score: 0) == .depleted)
    #expect(ReadinessBand.classify(score: 33) == .depleted)
    #expect(ReadinessBand.classify(score: 34) == .balanced)
    #expect(ReadinessBand.classify(score: 66) == .balanced)
    #expect(ReadinessBand.classify(score: 67) == .primed)
    #expect(ReadinessBand.classify(score: 100) == .primed)
  }

  @Test("narrow oscillation around threshold holds previous band")
  func oscillationHoldsBand() {
    #expect(ReadinessBand.classify(score: 35, previous: .depleted) == .depleted)
    #expect(ReadinessBand.classify(score: 36, previous: .depleted) == .depleted)
    #expect(ReadinessBand.classify(score: 65, previous: .primed) == .primed)
    #expect(ReadinessBand.classify(score: 66, previous: .primed) == .primed)
    #expect(ReadinessBand.classify(score: 35, previous: .balanced) == .balanced)
    #expect(ReadinessBand.classify(score: 66, previous: .balanced) == .balanced)
  }

  @Test("decisive move crosses band boundary")
  func decisiveCrossing() {
    #expect(ReadinessBand.classify(score: 37, previous: .depleted) == .balanced)
    #expect(ReadinessBand.classify(score: 70, previous: .balanced) == .primed)
    #expect(ReadinessBand.classify(score: 63, previous: .primed) == .balanced)
    #expect(ReadinessBand.classify(score: 30, previous: .balanced) == .depleted)
  }
}
