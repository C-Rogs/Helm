import Foundation

enum StabilityCalculator {
  struct Result: Sendable, Equatable {
    let stabilityScore: Double
    let confidenceFactor: Double
  }

  static func compute(nightlyHRV: [Double]) -> Result {
    let recent = Array(nightlyHRV.suffix(7))
    guard recent.count >= 3 else {
      return Result(stabilityScore: 50, confidenceFactor: 0.85)
    }

    let mean = recent.reduce(0, +) / Double(recent.count)
    guard mean > 0 else {
      return Result(stabilityScore: 50, confidenceFactor: 0.85)
    }

    let variance = recent.reduce(0) { $0 + pow($1 - mean, 2) } / Double(recent.count)
    let coefficientOfVariation = sqrt(variance) / mean
    let stability = 100 * (1 - min(max(coefficientOfVariation / 0.25, 0), 1))
    let factor = 0.7 + 0.3 * (stability / 100)
    return Result(stabilityScore: stability, confidenceFactor: factor)
  }
}
