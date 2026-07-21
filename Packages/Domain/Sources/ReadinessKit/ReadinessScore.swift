import Foundation

public enum ReadinessBand: String, Sendable, Hashable, Codable {
  case depleted
  case balanced
  case primed

  public static func classify(score: Int) -> ReadinessBand {
    if score < 34 { return .depleted }
    if score < 67 { return .balanced }
    return .primed
  }
}

public enum ReadinessConfidence: String, Sendable, Hashable, Codable {
  case high
  case medium
  case low
}

public enum HRVZBand: String, Sendable, Hashable, Codable {
  case elevated
  case typical
  case suppressed
  case insufficientData

  public static func classify(z: Double?) -> HRVZBand {
    guard let z else { return .insufficientData }
    if z > 0.75 { return .elevated }
    if z < -0.75 { return .suppressed }
    return .typical
  }
}

public struct ReadinessContributorBreakdown: Sendable, Hashable, Codable, Equatable {
  public let zHRV: Double?
  public let zRestingHR: Double?
  public let zSleep: Double?
  public let zRespiratory: Double?
  public let zTemperature: Double?
  public let zStrain: Double?
  public let zComposite: Double?
  public let rawScore: Double?
  public let dampedScore: Double?

  public init(
    zHRV: Double?,
    zRestingHR: Double?,
    zSleep: Double?,
    zRespiratory: Double?,
    zTemperature: Double?,
    zStrain: Double?,
    zComposite: Double?,
    rawScore: Double?,
    dampedScore: Double?
  ) {
    self.zHRV = zHRV
    self.zRestingHR = zRestingHR
    self.zSleep = zSleep
    self.zRespiratory = zRespiratory
    self.zTemperature = zTemperature
    self.zStrain = zStrain
    self.zComposite = zComposite
    self.rawScore = rawScore
    self.dampedScore = dampedScore
  }
}

public struct ReadinessScore: Sendable, Hashable, Codable, Equatable {
  public let score: Int
  public let band: ReadinessBand
  public let confidence: ReadinessConfidence
  public let confidenceValue: Double
  public let hrvBand: HRVZBand
  public let validNights: Int
  public let stabilityScore: Double
  public let contributors: ReadinessContributorBreakdown
  public let effectiveHRVMilliseconds: Double?
  public let restingHeartRate: Int?

  public init(
    score: Int,
    band: ReadinessBand,
    confidence: ReadinessConfidence,
    confidenceValue: Double,
    hrvBand: HRVZBand,
    validNights: Int,
    stabilityScore: Double,
    contributors: ReadinessContributorBreakdown,
    effectiveHRVMilliseconds: Double?,
    restingHeartRate: Int?
  ) {
    self.score = score
    self.band = band
    self.confidence = confidence
    self.confidenceValue = confidenceValue
    self.hrvBand = hrvBand
    self.validNights = validNights
    self.stabilityScore = stabilityScore
    self.contributors = contributors
    self.effectiveHRVMilliseconds = effectiveHRVMilliseconds
    self.restingHeartRate = restingHeartRate
  }
}
