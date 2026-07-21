import Core
import Foundation

struct HRVBalanceResult: Sendable, Equatable {
  let zHRV: Double?
  let zBand: HRVZBand
  let nightlyHRV: [Double]
  let validNights: Int
}

enum HRVAnalyzer {
  static let hrvSigmaFloor = 0.5

  struct TimestampedSample: Sendable, Equatable {
    let timestamp: Date
    let sdnnMilliseconds: Double
  }

  struct SleepInterval: Sendable, Equatable {
    let start: Date
    let end: Date
  }

  static func medianSDNN(
    samples: [TimestampedSample],
    inIntervals intervals: [SleepInterval]
  ) -> Double? {
    guard !intervals.isEmpty else { return nil }
    let values = samples.compactMap { sample -> Double? in
      let inSleep = intervals.contains { interval in
        sample.timestamp >= interval.start && sample.timestamp <= interval.end
      }
      return inSleep ? sample.sdnnMilliseconds : nil
    }
    return median(values)
  }

  static func medianSDNNMorningWindow(
    samples: [TimestampedSample],
    day: HelmDay,
    calendar: Calendar
  ) -> Double? {
    guard let dayStart = day.startInstant(calendar: calendar) else { return nil }
    guard let windowEnd = calendar.date(byAdding: .hour, value: 8, to: dayStart) else { return nil }
    let values = samples.compactMap { sample -> Double? in
      guard sample.timestamp >= dayStart, sample.timestamp <= windowEnd else { return nil }
      return sample.sdnnMilliseconds
    }
    return median(values)
  }

  static func hrvBalance(
    history: [ReadinessDayInput],
    through day: HelmDay,
    chronicBaseline: ReadinessBaseline?
  ) -> HRVBalanceResult {
    let nightly = history
      .filter { $0.helmDay <= day }
      .sorted { $0.helmDay < $1.helmDay }
      .compactMap(\.effectiveHRVMilliseconds)

    let validNights = nightly.count
    guard validNights >= 4 else {
      return HRVBalanceResult(
        zHRV: nil,
        zBand: .insufficientData,
        nightlyHRV: nightly,
        validNights: validNights
      )
    }

    let acuteMean = BaselineTracker.arithmeticMean(Array(nightly.suffix(7)))
    let mediumMean = BaselineTracker.arithmeticMean(Array(nightly.suffix(14)))
    let chronic = chronicBaseline
      ?? BaselineTracker.ewmaBaseline(values: Array(nightly.suffix(min(60, nightly.count))))

    guard let acuteMean, let mediumMean, let chronic else {
      return HRVBalanceResult(
        zHRV: nil,
        zBand: .insufficientData,
        nightlyHRV: nightly,
        validNights: validNights
      )
    }

    let zAcute = BaselineTracker.zScore(
      value: acuteMean,
      baseline: chronic,
      sigmaFloor: hrvSigmaFloor
    )
    let zMedium = BaselineTracker.zScore(
      value: mediumMean,
      baseline: chronic,
      sigmaFloor: hrvSigmaFloor
    )
    let zHRV = 0.70 * zAcute + 0.30 * zMedium

    return HRVBalanceResult(
      zHRV: zHRV,
      zBand: HRVZBand.classify(z: zHRV),
      nightlyHRV: nightly,
      validNights: validNights
    )
  }

  private static func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
      return (sorted[mid - 1] + sorted[mid]) / 2
    }
    return sorted[mid]
  }
}
