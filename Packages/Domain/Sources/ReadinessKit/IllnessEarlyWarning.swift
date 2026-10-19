import Core
import Foundation

/// Fired biometric signals that together suggest early illness / overreach strain.
public enum IllnessEarlyWarningSignal: String, Sendable, Hashable, Codable, CaseIterable {
  case restingHeartRate
  case hrv
  case wristTemperature
  case respiratoryRate

  public var label: String {
    switch self {
    case .restingHeartRate: "resting HR"
    case .hrv: "HRV"
    case .wristTemperature: "wrist temperature"
    case .respiratoryRate: "respiration"
    }
  }
}

/// NOOP-style early-illness / elevated-strain signature from personal baselines.
/// Wellness nudge only. Not a diagnosis or medical device signal.
public struct IllnessEarlyWarning: Sendable, Hashable, Codable, Equatable, Identifiable {
  public let id: String
  public let helmDay: HelmDay
  public let signals: [IllnessEarlyWarningSignal]
  public let message: String

  public init(
    id: String,
    helmDay: HelmDay,
    signals: [IllnessEarlyWarningSignal],
    message: String
  ) {
    self.id = id
    self.helmDay = helmDay
    self.signals = signals
    self.message = message
  }
}

public enum IllnessEarlyWarningDetector {
  public static let recentDayCount = 2
  public static let baselineDayCount = 28
  public static let baselineEndOffsetDays = 3
  public static let minimumBaselineDays = 14

  public static let restingHRDeltaBPM = 5.0
  public static let hrvRatioThreshold = 0.80
  public static let wristTemperatureDeltaCelsius = 0.6
  public static let respiratoryRateDelta = 1.5

  /// Detect early illness / strain signature for `day`.
  ///
  /// Recent window: last `recentDayCount` days through `day`.
  /// Baseline window: `baselineDayCount` days ending `baselineEndOffsetDays` before `day`.
  /// Fires when at least two anomaly rules trip.
  public static func detect(
    history: [ReadinessDayInput],
    day: HelmDay,
    calendar: Calendar = .current
  ) -> IllnessEarlyWarning? {
    let sorted = history.sorted { $0.helmDay < $1.helmDay }
    let recentStart = day.adding(days: -(recentDayCount - 1), calendar: calendar)
    let baselineEnd = day.adding(days: -baselineEndOffsetDays, calendar: calendar)
    let baselineStart = baselineEnd.adding(days: -(baselineDayCount - 1), calendar: calendar)

    let recent = sorted.filter { $0.helmDay >= recentStart && $0.helmDay <= day }
    let baseline = sorted.filter { $0.helmDay >= baselineStart && $0.helmDay <= baselineEnd }

    guard recent.count >= 1 else { return nil }

    var fired: [IllnessEarlyWarningSignal] = []

    if let anomaly = restingHRAnomaly(recent: recent, baseline: baseline), anomaly {
      fired.append(.restingHeartRate)
    }
    if let anomaly = hrvAnomaly(recent: recent, baseline: baseline), anomaly {
      fired.append(.hrv)
    }
    if let anomaly = wristTemperatureAnomaly(recent: recent, baseline: baseline), anomaly {
      fired.append(.wristTemperature)
    }
    if let anomaly = respiratoryAnomaly(recent: recent, baseline: baseline), anomaly {
      fired.append(.respiratoryRate)
    }

    guard fired.count >= 2 else { return nil }

    let signalKey = fired.map(\.rawValue).sorted().joined(separator: "+")
    return IllnessEarlyWarning(
      id: "illness_\(day.formatted)_\(signalKey)",
      helmDay: day,
      signals: fired,
      message: message(for: fired)
    )
  }

  private static func restingHRAnomaly(
    recent: [ReadinessDayInput],
    baseline: [ReadinessDayInput]
  ) -> Bool? {
    guard let recentMean = mean(recent.compactMap { $0.restingHeartRate.map(Double.init) }),
          let baselineMean = mean(baseline.compactMap { $0.restingHeartRate.map(Double.init) }),
          baseline.compactMap(\.restingHeartRate).count >= minimumBaselineDays
    else { return nil }
    return recentMean >= baselineMean + restingHRDeltaBPM
  }

  private static func hrvAnomaly(
    recent: [ReadinessDayInput],
    baseline: [ReadinessDayInput]
  ) -> Bool? {
    guard let recentMean = mean(recent.compactMap(\.effectiveHRVMilliseconds)),
          let baselineMean = mean(baseline.compactMap(\.effectiveHRVMilliseconds)),
          baseline.compactMap(\.effectiveHRVMilliseconds).count >= minimumBaselineDays,
          baselineMean > 0
    else { return nil }
    return recentMean <= baselineMean * hrvRatioThreshold
  }

  private static func wristTemperatureAnomaly(
    recent: [ReadinessDayInput],
    baseline: [ReadinessDayInput]
  ) -> Bool? {
    _ = baseline
    // Metric is already a deviation from personal typical; NOOP flags recent mean ≥ +0.6 °C.
    guard let recentMean = mean(recent.compactMap(\.wristTemperatureDeltaCelsius)) else {
      return nil
    }
    return recentMean >= wristTemperatureDeltaCelsius
  }

  private static func respiratoryAnomaly(
    recent: [ReadinessDayInput],
    baseline: [ReadinessDayInput]
  ) -> Bool? {
    guard let recentMean = mean(recent.compactMap(\.respiratoryRate)),
          let baselineMean = mean(baseline.compactMap(\.respiratoryRate)),
          baseline.compactMap(\.respiratoryRate).count >= minimumBaselineDays
    else { return nil }
    return recentMean >= baselineMean + respiratoryRateDelta
  }

  private static func mean(_ values: [Double]) -> Double? {
    BaselineTracker.arithmeticMean(values)
  }

  private static func message(for signals: [IllnessEarlyWarningSignal]) -> String {
    let labels = signals.map(\.label)
    let joined: String
    switch labels.count {
    case 0:
      joined = "several signals"
    case 1:
      joined = labels[0]
    case 2:
      joined = "\(labels[0]) and \(labels[1])"
    default:
      let head = labels.dropLast().joined(separator: ", ")
      joined = "\(head), and \(labels.last!)"
    }
    return "Body looks strained (\(joined)). Consider taking it easy. Wellness signal only, not a diagnosis."
  }
}
