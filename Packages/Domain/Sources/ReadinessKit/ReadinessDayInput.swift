import Core
import Foundation

/// One logical day's inputs for ARC readiness scoring.
public struct ReadinessDayInput: Sendable, Hashable, Codable, Identifiable {
  public let helmDay: HelmDay
  /// Median SDNN (ms) during confirmed asleep stages.
  public let hrvSleepSDNN: DurationMs?
  /// Median SDNN (ms) between 00:00 and 08:00 local when stage filter is unavailable.
  public let hrvMorningSDNN: DurationMs?
  /// HealthKit discrete daily SDNN average (fallback).
  public let hrvDailyAverage: DurationMs?
  public let restingHeartRate: Int?
  public let sleepDurationHours: Double?
  public let sleepEfficiency: Double?
  public let deepSleepMinutes: Double?
  public let remSleepMinutes: Double?
  public let respiratoryRate: Double?
  public let wristTemperatureDeltaCelsius: Double?
  /// Prior calendar day's Edwards TRIMP load.
  public let priorDayTRIMP: Double?

  public var id: HelmDay { helmDay }

  public init(
    helmDay: HelmDay,
    hrvSleepSDNN: DurationMs? = nil,
    hrvMorningSDNN: DurationMs? = nil,
    hrvDailyAverage: DurationMs? = nil,
    restingHeartRate: Int? = nil,
    sleepDurationHours: Double? = nil,
    sleepEfficiency: Double? = nil,
    deepSleepMinutes: Double? = nil,
    remSleepMinutes: Double? = nil,
    respiratoryRate: Double? = nil,
    wristTemperatureDeltaCelsius: Double? = nil,
    priorDayTRIMP: Double? = nil
  ) {
    self.helmDay = helmDay
    self.hrvSleepSDNN = hrvSleepSDNN
    self.hrvMorningSDNN = hrvMorningSDNN
    self.hrvDailyAverage = hrvDailyAverage
    self.restingHeartRate = restingHeartRate
    self.sleepDurationHours = sleepDurationHours
    self.sleepEfficiency = sleepEfficiency
    self.deepSleepMinutes = deepSleepMinutes
    self.remSleepMinutes = remSleepMinutes
    self.respiratoryRate = respiratoryRate
    self.wristTemperatureDeltaCelsius = wristTemperatureDeltaCelsius
    self.priorDayTRIMP = priorDayTRIMP
  }

  /// Priority: sleep-window median, 00:00-08:00 fallback, daily average.
  public var effectiveHRVMilliseconds: Double? {
    hrvSleepSDNN?.milliseconds.doubleValue
      ?? hrvMorningSDNN?.milliseconds.doubleValue
      ?? hrvDailyAverage.map { Double($0.milliseconds) }
  }

  public var hasValidNight: Bool {
    effectiveHRVMilliseconds != nil
  }
}

private extension Int {
  var doubleValue: Double { Double(self) }
}
