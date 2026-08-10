import Foundation

public enum StrainCalculator {
  /// Edwards TRIMP from heart-rate samples during a workout.
  public static func edwardsTRIMP(
    heartRateSamples: [Double],
    restingHR: Double,
    hrMax: Double
  ) -> Double {
    guard !heartRateSamples.isEmpty, hrMax > restingHR else { return 0 }

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
      trimp += weight
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
