import Foundation

public enum StrainCalculator {
  /// Edwards TRIMP from heart-rate samples during a workout.
  ///
  /// Canonical Edwards TRIMP integrates zone weight over *time*. `secondsBetweenSamples`
  /// converts a per-sample weight sum into a minutes-based integral; when unknown, callers
  /// that only have uniform-rate samples may pass the expected sampling interval.
  public static func edwardsTRIMP(
    heartRateSamples: [Double],
    restingHR: Double,
    hrMax: Double,
    secondsBetweenSamples: Double? = nil
  ) -> Double {
    guard !heartRateSamples.isEmpty, hrMax > restingHR else { return 0 }

    let sampleWeightMinutes = (secondsBetweenSamples ?? 60) / 60
    var trimp = 0.0
    for bpm in heartRateSamples {
      let hrr = (bpm - restingHR) / (hrMax - restingHR) * 100
      let weight: Double
      switch hrr {
      case ..<70: weight = 1
      case ..<80: weight = 2
      case ..<90: weight = 3
      case ..<100: weight = 4
      default: weight = 5
      }
      trimp += weight * sampleWeightMinutes
    }
    return trimp
  }

  /// Edwards TRIMP from timestamped readings, integrating each reading's zone weight over
  /// its actual duration (time since the previous reading, clamped). Robust to variable
  /// sample rates and gaps.
  public static func edwardsTRIMP(
    datedHeartRateReadings: [(date: Date, bpm: Double)],
    workoutStart: Date,
    workoutEnd: Date,
    restingHR: Double,
    hrMax: Double
  ) -> Double {
    guard !datedHeartRateReadings.isEmpty, hrMax > restingHR else { return 0 }

    let sorted = datedHeartRateReadings.sorted { $0.date < $1.date }
    var trimp = 0.0

    for (index, reading) in sorted.enumerated() {
      guard reading.bpm > 0 else { continue }
      let segmentStart = max(reading.date, workoutStart)
      let segmentEnd: Date
      if index + 1 < sorted.count {
        segmentEnd = min(sorted[index + 1].date, workoutEnd)
      } else {
        segmentEnd = workoutEnd
      }
      let minutes = segmentEnd.timeIntervalSince(segmentStart) / 60
      guard minutes > 0 else { continue }

      let hrr = (reading.bpm - restingHR) / (hrMax - restingHR) * 100
      let weight: Double
      switch hrr {
      case ..<70: weight = 1
      case ..<80: weight = 2
      case ..<90: weight = 3
      case ..<100: weight = 4
      default: weight = 5
      }
      trimp += weight * minutes
    }
    return trimp
  }

  /// Tanaka (208 - 0.7 x age) vs observed 99.5th percentile; spec uses the higher value.
  public static func hrMax(observedHRSamples: [Double], age: Int?) -> Double {
    let tanaka = age.map { 208.0 - 0.7 * Double($0) }
    let observed = percentile995(observedHRSamples)
    switch (tanaka, observed) {
    case let (t?, o?) where o > 120:
      return max(o, t)
    case let (t?, _):
      return t
    case let (_, o?) where o > 120:
      return o
    default:
      return 185
    }
  }

  public static func strainZ(
    priorDayTRIMP: Double?,
    historicalTRIMP: [Double],
    seededP75: Double?
  ) -> Double? {
    guard let priorDayTRIMP, !historicalTRIMP.isEmpty else { return nil }
    let p75 = seededP75 ?? percentile75(historicalTRIMP)
    guard let p75, p75 > 0 else { return nil }

    let ratio = priorDayTRIMP / p75
    let baseline = ReadinessBaseline(mean: 1.0, robustSigma: 0.35)
    return BaselineTracker.zInverted(value: ratio, baseline: baseline, sigmaFloor: 0.2)
  }

  public static func percentile75(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let index = Int((Double(sorted.count - 1) * 0.75).rounded())
    return sorted[max(0, min(sorted.count - 1, index))]
  }

  private static func percentile995(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let index = Int((Double(sorted.count - 1) * 0.995).rounded())
    return sorted[max(0, min(sorted.count - 1, index))]
  }
}
