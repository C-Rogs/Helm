import Foundation

public struct ReadinessBaseline: Sendable, Hashable, Codable, Equatable {
  public let mean: Double
  public let robustSigma: Double

  public init(mean: Double, robustSigma: Double) {
    self.mean = mean
    self.robustSigma = robustSigma
  }
}

/// Pre-computed EWMA baselines from historical backfill.
public struct ReadinessBaselineState: Sendable, Hashable, Codable, Equatable {
  public var hrvChronic: ReadinessBaseline?
  public var restingHR: ReadinessBaseline?
  public var sleepDuration: ReadinessBaseline?
  public var sleepEfficiency: ReadinessBaseline?
  public var sleepStageQuality: ReadinessBaseline?
  public var sleepDebt: ReadinessBaseline?
  public var respiratoryRate: ReadinessBaseline?
  public var wristTemperature: ReadinessBaseline?
  public var trimpP75: Double?
  public var seededNightCount: Int

  public init(
    hrvChronic: ReadinessBaseline? = nil,
    restingHR: ReadinessBaseline? = nil,
    sleepDuration: ReadinessBaseline? = nil,
    sleepEfficiency: ReadinessBaseline? = nil,
    sleepStageQuality: ReadinessBaseline? = nil,
    sleepDebt: ReadinessBaseline? = nil,
    respiratoryRate: ReadinessBaseline? = nil,
    wristTemperature: ReadinessBaseline? = nil,
    trimpP75: Double? = nil,
    seededNightCount: Int = 0
  ) {
    self.hrvChronic = hrvChronic
    self.restingHR = restingHR
    self.sleepDuration = sleepDuration
    self.sleepEfficiency = sleepEfficiency
    self.sleepStageQuality = sleepStageQuality
    self.sleepDebt = sleepDebt
    self.respiratoryRate = respiratoryRate
    self.wristTemperature = wristTemperature
    self.trimpP75 = trimpP75
    self.seededNightCount = seededNightCount
  }
}

enum BaselineTracker {
  static let halfLifeDays = 14.0

  static var alpha: Double {
    1.0 - exp(log(0.5) / halfLifeDays)
  }

  static func ewmaBaseline(values: [Double], alpha: Double = alpha) -> ReadinessBaseline? {
    guard !values.isEmpty else { return nil }

    var mean = values[0]
    var mad = 0.0

    for value in values.dropFirst() {
      let deviation = abs(value - mean)
      mad = alpha * deviation + (1 - alpha) * mad
      mean = alpha * value + (1 - alpha) * mean
    }

    let robustSigma = max(1.253 * mad, 0)
    return ReadinessBaseline(mean: mean, robustSigma: robustSigma)
  }

  static func zScore(
    value: Double,
    baseline: ReadinessBaseline,
    sigmaFloor: Double
  ) -> Double {
    let sigma = max(baseline.robustSigma, sigmaFloor)
    guard sigma > 0 else { return 0 }
    return (value - baseline.mean) / sigma
  }

  static func zInverted(
    value: Double,
    baseline: ReadinessBaseline,
    sigmaFloor: Double
  ) -> Double {
    -zScore(value: value, baseline: baseline, sigmaFloor: sigmaFloor)
  }

  static func arithmeticMean(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }
}
