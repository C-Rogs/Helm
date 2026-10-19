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

  @Test("missing sleep weight redistributes onto present required terms")
  func missingSleepRedistribution() {
    let withoutSleep = ReadinessKit.compositeZ(
      zHRV: 0.5,
      zRHR: 0.2,
      zSleep: nil,
      zResp: nil,
      zTemp: nil,
      zStrain: nil
    )
    let withBadSleep = ReadinessKit.compositeZ(
      zHRV: 0.5,
      zRHR: 0.2,
      zSleep: -1.0,
      zResp: nil,
      zTemp: nil,
      zStrain: nil
    )
    #expect(withoutSleep != nil)
    #expect(withBadSleep != nil)

    // Sleep weight (0.22) + missing optional (0.18) land on HRV/RHR only.
    let hrvW = 0.42 + 0.22 * (0.42 / 0.60)
    let rhrW = 0.18 + 0.22 * (0.18 / 0.60)
    let requiredTotal = hrvW + rhrW
    let missingOptional = 0.18
    let hrvEff = hrvW + missingOptional * (hrvW / requiredTotal)
    let rhrEff = rhrW + missingOptional * (rhrW / requiredTotal)
    let expected = 0.5 * hrvEff + 0.2 * rhrEff
    #expect(abs((withoutSleep ?? 0) - expected) < 0.01)
    #expect((withoutSleep ?? 0) > (withBadSleep ?? 0))
  }

  @Test("nil sleep duration today does not emit zSleep even with historical debt")
  func missingSleepDoesNotTankFromDebt() {
    // Short prior nights so debt would be elevated if scored alone.
    var history = baselineHistory(nights: 20, sleepHours: 5.5)
    history[history.count - 1] = ReadinessDayInput(
      helmDay: endDay,
      hrvDailyAverage: DurationMs(milliseconds: 50),
      restingHeartRate: 60,
      sleepDurationHours: nil,
      sleepEfficiency: nil,
      deepSleepMinutes: nil,
      remSleepMinutes: nil
    )

    let sleep = SleepAnalyzer.analyze(history: history, day: endDay, seededBaselines: nil)
    #expect(sleep.zSleep == nil)

    let missingScore = ReadinessKit.readiness(for: endDay, history: history)
    #expect(missingScore != nil)
    #expect(missingScore?.contributors.zSleep == nil)

    // Measured short sleep still penalizes vs unknown sleep (CAM-83).
    var withShort = history
    withShort[withShort.count - 1] = ReadinessDayInput(
      helmDay: endDay,
      hrvDailyAverage: DurationMs(milliseconds: 50),
      restingHeartRate: 60,
      sleepDurationHours: 4.0,
      sleepEfficiency: 0.7,
      deepSleepMinutes: 20,
      remSleepMinutes: 40
    )
    let shortScore = ReadinessKit.readiness(for: endDay, history: withShort)
    #expect(shortScore?.contributors.zSleep != nil)
    #expect((missingScore?.score ?? 0) > (shortScore?.score ?? 100))
  }

  @Test("measured short sleep still penalizes readiness")
  func measuredShortSleepPenalizes() {
    var short = baselineHistory(nights: 29, sleepHours: 7.5)
    short.append(
      ReadinessDayInput(
        helmDay: endDay,
        hrvDailyAverage: DurationMs(milliseconds: 50),
        restingHeartRate: 60,
        sleepDurationHours: 4.0,
        sleepEfficiency: 0.7,
        deepSleepMinutes: 20,
        remSleepMinutes: 40
      )
    )
    var typical = baselineHistory(nights: 29, sleepHours: 7.5)
    typical.append(
      ReadinessDayInput(
        helmDay: endDay,
        hrvDailyAverage: DurationMs(milliseconds: 50),
        restingHeartRate: 60,
        sleepDurationHours: 7.5,
        sleepEfficiency: 0.9,
        deepSleepMinutes: 50,
        remSleepMinutes: 90
      )
    )
    let shortScore = ReadinessKit.readiness(for: endDay, history: short)
    let typicalScore = ReadinessKit.readiness(for: endDay, history: typical)
    #expect(shortScore?.contributors.zSleep != nil)
    #expect((shortScore?.score ?? 100) < (typicalScore?.score ?? 0))
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

  @Test("incremental baseline update produces same result as batch EWMA")
  func incrementalMatchesBatch() {
    let history = baselineHistory(nights: 30, hrvMilliseconds: 50)
    let seeded = ReadinessKit.seedBaselines(from: history)

    // Simulate one new day
    let today = ReadinessDayInput(
      helmDay: endDay.adding(days: 1),
      hrvDailyAverage: DurationMs(milliseconds: 55),
      restingHeartRate: 58,
      sleepDurationHours: 8.0,
      sleepEfficiency: 0.92,
      deepSleepMinutes: 55,
      remSleepMinutes: 95
    )
    let updated = seeded.updating(today: today, history: history)

    // Batch baseline from full history + today
    let fullHistory = history + [today]
    let batch = ReadinessKit.seedBaselines(from: fullHistory)

    // EWMA means should be close (within 0.5 after 30 days of same values)
    if let batchHRV = batch.hrvChronic?.mean,
       let updatedHRV = updated.hrvChronic?.mean {
      #expect(abs(batchHRV - updatedHRV) < 0.5)
    }
    #expect(updated.seededNightCount == seeded.seededNightCount + 1)
  }

  @Test("incremental baseline update works from nil state")
  func incrementalFromNil() {
    let state = ReadinessBaselineState()
    let today = ReadinessDayInput(
      helmDay: endDay,
      hrvDailyAverage: DurationMs(milliseconds: 50),
      restingHeartRate: 60,
      sleepDurationHours: 7.5,
      sleepEfficiency: 0.9,
      deepSleepMinutes: 50,
      remSleepMinutes: 90
    )
    let updated = state.updating(today: today, history: [today])
    #expect(updated.hrvChronic?.mean == 50)
    #expect(updated.restingHR?.mean == 60)
    #expect(updated.sleepDuration?.mean == 7.5)
    #expect(updated.seededNightCount == 1)
  }

  @Test("incremental baseline update preserves missing fields")
  func incrementalPreservesMissing() {
    let history = baselineHistory(nights: 10, hrvMilliseconds: 50)
    let seeded = ReadinessKit.seedBaselines(from: history)

    let today = ReadinessDayInput(
      helmDay: endDay.adding(days: 1),
      hrvDailyAverage: DurationMs(milliseconds: 55),
      restingHeartRate: nil,  // no RHR today
      sleepDurationHours: nil,  // no sleep today
      sleepEfficiency: nil
    )
    let updated = seeded.updating(today: today, history: history)

    // HRV updated
    #expect(updated.hrvChronic?.mean != seeded.hrvChronic?.mean)
    // RHR unchanged (nil today)
    #expect(updated.restingHR?.mean == seeded.restingHR?.mean)
    // Sleep unchanged (nil today)
    #expect(updated.sleepDuration?.mean == seeded.sleepDuration?.mean)
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

  @Test("one recovered night after a suppressed week leaves depleted")
  func recoveredNightLeavesDepleted() {
    var history: [ReadinessDayInput] = []
    for offset in -20 ... -1 {
      let suppressed = offset >= -6
      history.append(
        ReadinessDayInput(
          helmDay: endDay.adding(days: offset),
          hrvDailyAverage: DurationMs(milliseconds: suppressed ? 45 : 60),
          restingHeartRate: 60,
          sleepDurationHours: 7.5,
          sleepEfficiency: 0.9,
          deepSleepMinutes: 50,
          remSleepMinutes: 90
        )
      )
    }
    history.append(
      ReadinessDayInput(
        helmDay: endDay,
        hrvDailyAverage: DurationMs(milliseconds: 75),
        restingHeartRate: 60,
        sleepDurationHours: 8.5,
        sleepEfficiency: 0.9,
        deepSleepMinutes: 50,
        remSleepMinutes: 90
      )
    )
    let baselines = ReadinessBaselineState(
      hrvChronic: ReadinessBaseline(mean: 60, robustSigma: 8),
      restingHR: ReadinessBaseline(mean: 60, robustSigma: 3),
      sleepDuration: ReadinessBaseline(mean: 7.5, robustSigma: 0.6),
      seededNightCount: history.count
    )
    let score = ReadinessKit.readiness(
      for: endDay,
      history: history,
      baselineState: baselines
    )
    #expect((score?.score ?? 0) >= 37)
    #expect(score?.band != .depleted)
    #expect((score?.contributors.zHRV ?? 0) > 0)
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
