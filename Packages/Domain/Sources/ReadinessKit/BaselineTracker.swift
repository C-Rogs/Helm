import Foundation

public struct ReadinessBaseline: Sendable, Hashable, Codable, Equatable {
  public let mean: Double
  public let robustSigma: Double

  public init(mean: Double, robustSigma: Double) {
    self.mean = mean
    self.robustSigma = robustSigma
  }

  /// Incremental EWMA update. Returns new baseline from one day's value.
  /// Alpha is the EWMA smoothing factor (0.048 for 14-day half-life).
  ///
  /// When sigma is established: values beyond 5σ are hard-rejected from the mean
  /// (spread still sees the deviation). Values inside that band are Winsor-clamped
  /// to ±3σ before folding into the mean. Cold start (sigma ≤ 0) is unclamped.
  public func updating(with value: Double) -> ReadinessBaseline {
    BaselineTracker.ewmaStep(current: self, value: value)
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

  /// Incrementally update all baselines from today's input and recent history.
  /// Returns new state - caller must persist.
  public func updating(
    today: ReadinessDayInput,
    history: [ReadinessDayInput]
  ) -> ReadinessBaselineState {
    var next = self

    if let hrv = today.effectiveHRVMilliseconds {
      next.hrvChronic = (hrvChronic ?? ReadinessBaseline(mean: hrv, robustSigma: 0))
        .updating(with: hrv)
      next.seededNightCount += 1
    }

    if let rhr = today.restingHeartRate {
      let rhrDouble = Double(rhr)
      next.restingHR = (restingHR ?? ReadinessBaseline(mean: rhrDouble, robustSigma: 0))
        .updating(with: rhrDouble)
    }

    if let duration = today.sleepDurationHours {
      next.sleepDuration = (sleepDuration ?? ReadinessBaseline(mean: duration, robustSigma: 0))
        .updating(with: duration)
    }

    if let efficiency = today.sleepEfficiency {
      next.sleepEfficiency = (sleepEfficiency ?? ReadinessBaseline(mean: efficiency, robustSigma: 0))
        .updating(with: efficiency)
    }

    if let stage = ReadinessKit.stageQuality(today) {
      next.sleepStageQuality = (sleepStageQuality ?? ReadinessBaseline(mean: stage, robustSigma: 0))
        .updating(with: stage)
    }

    if let resp = today.respiratoryRate {
      next.respiratoryRate = (respiratoryRate ?? ReadinessBaseline(mean: resp, robustSigma: 0))
        .updating(with: resp)
    }

    if let temp = today.wristTemperatureDeltaCelsius {
      next.wristTemperature = (wristTemperature ?? ReadinessBaseline(mean: temp, robustSigma: 0))
        .updating(with: temp)
    }

    // Sleep debt: today's deficit = sleep need baseline - today's duration.
    if let todayDuration = today.sleepDurationHours {
      let need = sleepDuration?.mean ?? todayDuration
      let deficit = max(0, need - todayDuration)
      next.sleepDebt = (sleepDebt ?? ReadinessBaseline(mean: deficit, robustSigma: 0))
        .updating(with: deficit)
    }

    // TRIMP P75: compute from recent history (30-day window).
    let trimpValues = history.compactMap(\.priorDayTRIMP)
    if !trimpValues.isEmpty {
      next.trimpP75 = StrainCalculator.percentile75(trimpValues)
    }

    return next
  }
}

enum BaselineTracker {
  static let halfLifeDays = 14.0
  /// Hard-reject threshold: do not fold into the center beyond this many σ.
  static let hardRejectSigmaMultiple = 5.0
  /// Winsor clamp band applied to values that pass the hard-reject gate.
  static let winsorSigmaMultiple = 3.0

  static var alpha: Double {
    1.0 - exp(log(0.5) / halfLifeDays)
  }

  static func ewmaBaseline(values: [Double], alpha: Double = alpha) -> ReadinessBaseline? {
    _ = alpha
    guard let first = values.first else { return nil }

    var baseline = ReadinessBaseline(mean: first, robustSigma: 0)
    for value in values.dropFirst() {
      baseline = ewmaStep(current: baseline, value: value)
    }
    return baseline
  }

  /// Shared EWMA step used by batch seed and incremental `ReadinessBaseline.updating`.
  static func ewmaStep(current: ReadinessBaseline, value: Double) -> ReadinessBaseline {
    let smoothing = alpha
    let sigma = current.robustSigma
    let mad = sigma / 1.253

    // Cold start: no clamp until sigma is meaningful.
    guard sigma > 0 else {
      let deviation = abs(value - current.mean)
      let newMad = smoothing * deviation + (1 - smoothing) * mad
      let newMean = smoothing * value + (1 - smoothing) * current.mean
      return ReadinessBaseline(mean: newMean, robustSigma: max(1.253 * newMad, 0))
    }

    let deviationFromMean = abs(value - current.mean)

    // Hard reject: skip mean update; still let spread see the deviation.
    if deviationFromMean > hardRejectSigmaMultiple * sigma {
      let newMad = smoothing * deviationFromMean + (1 - smoothing) * mad
      return ReadinessBaseline(mean: current.mean, robustSigma: max(1.253 * newMad, 0))
    }

    let halfWidth = winsorSigmaMultiple * sigma
    let clamped = min(max(value, current.mean - halfWidth), current.mean + halfWidth)
    let newMean = smoothing * clamped + (1 - smoothing) * current.mean
    // Spread tracks unclamped deviation so real physiological change still lands.
    let deviation = abs(value - newMean)
    let newMad = smoothing * deviation + (1 - smoothing) * mad
    return ReadinessBaseline(mean: newMean, robustSigma: max(1.253 * newMad, 0))
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
