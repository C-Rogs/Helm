import Core
import Foundation

enum SleepAnalyzer {
  struct Result: Sendable, Equatable {
    let zDuration: Double?
    let zEfficiency: Double?
    let zStageQuality: Double?
    let zDebt: Double?
    let zSleep: Double?
  }

  private static let durationWeight = 0.35
  private static let efficiencyWeight = 0.25
  private static let stageWeight = 0.20
  private static let debtWeight = 0.20
  private static let sleepSigmaFloor = 0.3

  static func analyze(
    history: [ReadinessDayInput],
    day: HelmDay,
    seededBaselines: ReadinessBaselineState?
  ) -> Result {
    let prior = history.filter { $0.helmDay < day }.sorted { $0.helmDay < $1.helmDay }
    let today = history.first { $0.helmDay == day }

    let durationBaseline = seededBaselines?.sleepDuration
      ?? BaselineTracker.ewmaBaseline(values: prior.compactMap(\.sleepDurationHours))
    let efficiencyBaseline = seededBaselines?.sleepEfficiency
      ?? BaselineTracker.ewmaBaseline(values: prior.compactMap(\.sleepEfficiency))
    let stageBaseline = seededBaselines?.sleepStageQuality
      ?? BaselineTracker.ewmaBaseline(values: prior.compactMap(stageQuality))

    let zDuration = zTerm(
      value: today?.sleepDurationHours,
      baseline: durationBaseline,
      floor: sleepSigmaFloor
    )
    let zEfficiency = zTerm(
      value: today?.sleepEfficiency.map { min(max($0, 0.5), 1.0) },
      baseline: efficiencyBaseline,
      floor: sleepSigmaFloor
    )
    let zStage = zTerm(
      value: today.flatMap(stageQuality),
      baseline: stageBaseline,
      floor: sleepSigmaFloor
    )
    let zDebt = sleepDebtZ(
      history: history,
      day: day,
      seededDebtBaseline: seededBaselines?.sleepDebt
    )

    let zSleep = weightedComposite(
      terms: [
        (zDuration, durationWeight),
        (zEfficiency, efficiencyWeight),
        (zStage, stageWeight),
        (zDebt, debtWeight),
      ]
    )

    return Result(
      zDuration: zDuration,
      zEfficiency: zEfficiency,
      zStageQuality: zStage,
      zDebt: zDebt,
      zSleep: zSleep
    )
  }

  private static func stageQuality(_ input: ReadinessDayInput) -> Double? {
    guard let deep = input.deepSleepMinutes, let rem = input.remSleepMinutes else { return nil }
    return deep + rem
  }

  private static func zTerm(
    value: Double?,
    baseline: ReadinessBaseline?,
    floor: Double
  ) -> Double? {
    guard let value, let baseline else { return nil }
    return BaselineTracker.zScore(value: value, baseline: baseline, sigmaFloor: floor)
  }

  private static func sleepDebtZ(
    history: [ReadinessDayInput],
    day: HelmDay,
    seededDebtBaseline: ReadinessBaseline?
  ) -> Double? {
    let sorted = history.sorted { $0.helmDay < $1.helmDay }
    let prior = sorted.filter { $0.helmDay <= day }
    let durations = prior.compactMap(\.sleepDurationHours)
    guard durations.count >= 3 else { return nil }

    let need = BaselineTracker.ewmaBaseline(values: durations)?.mean
    guard let need else { return nil }

    let windowStart = day.adding(days: -13)
    let window = prior.filter { $0.helmDay >= windowStart && $0.helmDay <= day }

    var deficit = 0.0
    for snap in window {
      guard let actual = snap.sleepDurationHours else { continue }
      deficit += max(0, need - actual)
    }

    let debtHistory = rollingDebtSeries(history: sorted)
    let debtBaseline = seededDebtBaseline ?? BaselineTracker.ewmaBaseline(values: debtHistory)
    guard let debtBaseline else { return nil }
    return BaselineTracker.zInverted(
      value: deficit,
      baseline: debtBaseline,
      sigmaFloor: sleepSigmaFloor
    )
  }

  private static func rollingDebtSeries(history: [ReadinessDayInput]) -> [Double] {
    var series: [Double] = []
    let days = history.map(\.helmDay).sorted()
    guard let first = days.first else { return [] }

    for endDay in days where endDay >= first {
      let durations = history
        .filter { $0.helmDay <= endDay }
        .compactMap(\.sleepDurationHours)
      guard durations.count >= 3,
            let need = BaselineTracker.ewmaBaseline(values: durations)?.mean
      else { continue }

      let windowStart = endDay.adding(days: -13)
      var deficit = 0.0
      for snap in history where snap.helmDay >= windowStart && snap.helmDay <= endDay {
        guard let actual = snap.sleepDurationHours else { continue }
        deficit += max(0, need - actual)
      }
      series.append(deficit)
    }
    return series
  }

  private static func weightedComposite(terms: [(Double?, Double)]) -> Double? {
    var weightedSum = 0.0
    var weightTotal = 0.0
    for (term, weight) in terms {
      guard let term else { continue }
      weightedSum += term * weight
      weightTotal += weight
    }
    guard weightTotal > 0 else { return nil }
    return weightedSum / weightTotal
  }
}
