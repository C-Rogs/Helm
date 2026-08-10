import Core
import Foundation

/// Pure ARC readiness engine (Layer 1).
public enum ReadinessKit {
  private static let logisticK = 1.55
  private static let logisticZ0 = -0.18
  private static let anchorScore = 58.0

  private static let weightHRV = 0.42
  private static let weightRHR = 0.18
  private static let weightSleep = 0.22
  private static let weightResp = 0.06
  private static let weightTemp = 0.04
  private static let weightStrain = 0.08

  private static let rhrSigmaFloor = 1.0

  /// Count of nights with usable overnight HRV through `day`.
  public static func validNightCount(
    in history: [ReadinessDayInput],
    through day: HelmDay
  ) -> Int {
    history
      .filter { $0.helmDay <= day }
      .filter(\.hasValidNight)
      .count
  }

  /// UI copy for cold-start state. Nil when enough nights exist.
  public static func buildingBaselineMessage(validNights: Int) -> String? {
    guard validNights < 4 else { return nil }
    return "Building baseline (\(validNights)/4 nights)"
  }

  /// Pre-compute EWMA baselines from historical backfill so early scores are meaningful.
  public static func seedBaselines(
    from history: [ReadinessDayInput]
  ) -> ReadinessBaselineState {
    let sorted = history.sorted { $0.helmDay < $1.helmDay }
    let nightlyHRV = sorted.compactMap(\.effectiveHRVMilliseconds)
    let trimpHistory = sorted.compactMap(\.priorDayTRIMP)

    let debtHistory = sorted.compactMap { endDay -> Double? in
      let prior = sorted.filter { $0.helmDay <= endDay.helmDay }
      let durations = prior.compactMap(\.sleepDurationHours)
      guard durations.count >= 3,
            let need = BaselineTracker.ewmaBaseline(values: durations)?.mean
      else { return nil }

      let windowStart = endDay.helmDay.adding(days: -13)
      var deficit = 0.0
      for snap in prior where snap.helmDay >= windowStart {
        guard let actual = snap.sleepDurationHours else { continue }
        deficit += max(0, need - actual)
      }
      return deficit
    }

    return ReadinessBaselineState(
      hrvChronic: BaselineTracker.ewmaBaseline(values: Array(nightlyHRV.suffix(min(60, nightlyHRV.count)))),
      restingHR: BaselineTracker.ewmaBaseline(values: sorted.compactMap { $0.restingHeartRate.map(Double.init) }),
      sleepDuration: BaselineTracker.ewmaBaseline(values: sorted.compactMap(\.sleepDurationHours)),
      sleepEfficiency: BaselineTracker.ewmaBaseline(values: sorted.compactMap(\.sleepEfficiency)),
      sleepStageQuality: BaselineTracker.ewmaBaseline(values: sorted.compactMap(stageQuality)),
      sleepDebt: BaselineTracker.ewmaBaseline(values: debtHistory),
      respiratoryRate: BaselineTracker.ewmaBaseline(values: sorted.compactMap(\.respiratoryRate)),
      wristTemperature: BaselineTracker.ewmaBaseline(values: sorted.compactMap(\.wristTemperatureDeltaCelsius)),
      trimpP75: trimpPercentile75(trimpHistory),
      seededNightCount: nightlyHRV.count
    )
  }

  /// Compute ARC readiness for `day`. Returns nil when fewer than four valid nights exist.
  public static func readiness(
    for day: HelmDay,
    history: [ReadinessDayInput],
    baselineState: ReadinessBaselineState? = nil,
    calendar: Calendar = .current,
    cutoff: DayCutoff = .default
  ) -> ReadinessScore? {
    _ = calendar
    _ = cutoff

    let sorted = history.sorted { $0.helmDay < $1.helmDay }
    let prior = sorted.filter { $0.helmDay < day }
    let today = sorted.first { $0.helmDay == day }

    let hrvBalance = HRVAnalyzer.hrvBalance(
      history: sorted,
      through: day,
      chronicBaseline: baselineState?.hrvChronic
    )
    let validNights = hrvBalance.validNights
    guard validNights >= 4 else { return nil }

    let rhrBaseline = baselineState?.restingHR
      ?? BaselineTracker.ewmaBaseline(values: prior.compactMap { $0.restingHeartRate.map(Double.init) })
    let zRHR = today?.restingHeartRate.flatMap { value -> Double? in
      guard let rhrBaseline else { return nil }
      return BaselineTracker.zInverted(
        value: Double(value),
        baseline: rhrBaseline,
        sigmaFloor: rhrSigmaFloor
      )
    }

    let sleep = SleepAnalyzer.analyze(
      history: sorted,
      day: day,
      seededBaselines: baselineState
    )

    let respBaseline = baselineState?.respiratoryRate
      ?? BaselineTracker.ewmaBaseline(values: prior.compactMap(\.respiratoryRate))
    let zResp = today?.respiratoryRate.flatMap { value -> Double? in
      guard let respBaseline else { return nil }
      return BaselineTracker.zInverted(value: value, baseline: respBaseline, sigmaFloor: 0.5)
    }

    let tempBaseline = baselineState?.wristTemperature
      ?? BaselineTracker.ewmaBaseline(values: prior.compactMap(\.wristTemperatureDeltaCelsius))
    let zTemp = today?.wristTemperatureDeltaCelsius.flatMap { value -> Double? in
      guard let tempBaseline else { return nil }
      return BaselineTracker.zInverted(value: value, baseline: tempBaseline, sigmaFloor: 0.5)
    }

    let trimpHistory = prior.compactMap(\.priorDayTRIMP)
    let zStrain = StrainCalculator.strainZ(
      priorDayTRIMP: today?.priorDayTRIMP,
      historicalTRIMP: trimpHistory,
      seededP75: baselineState?.trimpP75
    )

    let zComposite = compositeZ(
      zHRV: hrvBalance.zHRV,
      zRHR: zRHR,
      zSleep: sleep.zSleep,
      zResp: zResp,
      zTemp: zTemp,
      zStrain: zStrain
    )

    let rawScore = zComposite.map { logisticSquash($0) }
    guard let dampedScore = dampedScore(raw: rawScore, validNights: validNights) else { return nil }

    let stability = StabilityCalculator.compute(nightlyHRV: hrvBalance.nightlyHRV)
    let missingRequired = missingRequiredCount(today: today, zSleep: sleep.zSleep)
    let confidenceValue = confidenceScore(
      validNights: validNights,
      missingRequired: missingRequired,
      stabilityFactor: stability.confidenceFactor
    )

    let rounded = Int(dampedScore.rounded())
    return ReadinessScore(
      score: rounded,
      band: ReadinessBand.classify(score: rounded),
      confidence: confidenceLabel(for: confidenceValue),
      confidenceValue: confidenceValue,
      hrvBand: hrvBalance.zBand,
      validNights: validNights,
      stabilityScore: stability.stabilityScore,
      contributors: ReadinessContributorBreakdown(
        zHRV: hrvBalance.zHRV,
        zRestingHR: zRHR,
        zSleep: sleep.zSleep,
        zRespiratory: zResp,
        zTemperature: zTemp,
        zStrain: zStrain,
        zComposite: zComposite,
        rawScore: rawScore,
        dampedScore: dampedScore
      ),
      effectiveHRVMilliseconds: today?.effectiveHRVMilliseconds,
      restingHeartRate: today?.restingHeartRate
    )
  }

  static func logisticSquash(_ z: Double) -> Double {
    100.0 / (1.0 + exp(-logisticK * (z - logisticZ0)))
  }

  static func compositeZ(
    zHRV: Double?,
    zRHR: Double?,
    zSleep: Double?,
    zResp: Double?,
    zTemp: Double?,
    zStrain: Double?
  ) -> Double? {
    var required: [(Double, Double)] = []
    if let zHRV { required.append((zHRV, weightHRV)) }
    if let zRHR { required.append((zRHR, weightRHR)) }
    if let zSleep { required.append((zSleep, weightSleep)) }

    guard !required.isEmpty else { return nil }

    var optional: [(Double, Double)] = []
    if let zResp { optional.append((zResp, weightResp)) }
    if let zTemp { optional.append((zTemp, weightTemp)) }
    if let zStrain { optional.append((zStrain, weightStrain)) }

    let presentOptionalWeight = optional.reduce(0) { $0 + $1.1 }
    let missingOptionalWeight = (weightResp + weightTemp + weightStrain) - presentOptionalWeight
    let requiredWeightTotal = required.reduce(0) { $0 + $1.1 }

    var effectiveRequired = required
    if missingOptionalWeight > 0, requiredWeightTotal > 0 {
      effectiveRequired = required.map { term, weight in
        (term, weight + missingOptionalWeight * (weight / requiredWeightTotal))
      }
    }

    let terms = effectiveRequired + optional
    let totalWeight = terms.reduce(0) { $0 + $1.1 }
    guard totalWeight > 0 else { return nil }

    return terms.reduce(0) { partial, term in
      partial + term.0 * (term.1 / totalWeight)
    }
  }

  static func confidenceLabel(for value: Double) -> ReadinessConfidence {
    if value >= 0.75 { return .high }
    if value >= 0.45 { return .medium }
    return .low
  }

  private static func dampedScore(raw: Double?, validNights: Int) -> Double? {
    guard let raw else { return nil }
    guard validNights >= 4 else { return nil }
    if validNights < 14 {
      return raw * 0.85 + anchorScore * 0.15
    }
    return raw
  }

  private static func missingRequiredCount(today: ReadinessDayInput?, zSleep: Double?) -> Int {
    var missing = 0
    if today?.effectiveHRVMilliseconds == nil { missing += 1 }
    if today?.restingHeartRate == nil { missing += 1 }
    if zSleep == nil { missing += 1 }
    return missing
  }

  private static func confidenceScore(
    validNights: Int,
    missingRequired: Int,
    stabilityFactor: Double
  ) -> Double {
    let nightsFactor = min(1.0, Double(validNights) / 14.0)
    let coverage = 1.0 - (Double(missingRequired) / 3.0)
    return max(0, nightsFactor * coverage * stabilityFactor)
  }

  public static func stageQuality(_ input: ReadinessDayInput) -> Double? {
    guard let deep = input.deepSleepMinutes, let rem = input.remSleepMinutes else { return nil }
    return deep + rem
  }

  private static func trimpPercentile75(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let index = Int((Double(sorted.count - 1) * 0.75).rounded())
    return sorted[max(0, min(sorted.count - 1, index))]
  }
}
