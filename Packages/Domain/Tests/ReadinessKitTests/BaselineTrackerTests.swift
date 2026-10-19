import Core
import Foundation
@testable import ReadinessKit
import Testing

@Suite("BaselineTracker")
struct BaselineTrackerTests {
  @Test("EWMA baseline tracks stable series")
  func ewmaTracksMean() {
    let values = Array(repeating: 50.0, count: 30)
    let baseline = BaselineTracker.ewmaBaseline(values: values)
    #expect(baseline != nil)
    #expect(abs((baseline?.mean ?? 0) - 50) < 0.5)
  }

  @Test("z-score at mean is zero")
  func zAtMean() {
    let baseline = ReadinessBaseline(mean: 50, robustSigma: 5)
    let z = BaselineTracker.zScore(value: 50, baseline: baseline, sigmaFloor: 0.5)
    #expect(abs(z) < 0.001)
  }

  @Test("inverted z flips sign for higher-is-worse metrics")
  func zInverted() {
    let baseline = ReadinessBaseline(mean: 60, robustSigma: 3)
    let z = BaselineTracker.zInverted(value: 66, baseline: baseline, sigmaFloor: 1)
    #expect(z < 0)
  }

  @Test("sigma floor prevents blow-up")
  func sigmaFloor() {
    let baseline = ReadinessBaseline(mean: 50, robustSigma: 0)
    let z = BaselineTracker.zScore(value: 55, baseline: baseline, sigmaFloor: 0.5)
    #expect(abs(z - 10) < 0.001)
  }

  @Test("hard-reject spike does not yank mean")
  func hardRejectPreservesMean() {
    // Slight variation so robust sigma is non-zero (flat series keeps sigma at 0).
    var series: [Double] = []
    for i in 0..<20 {
      series.append(50.0 + Double(i % 2))
    }
    let baseline = BaselineTracker.ewmaBaseline(values: series)!
    #expect(baseline.robustSigma > 0.1)
    let afterSpike = baseline.updating(with: baseline.mean + 20 * baseline.robustSigma)
    #expect(abs(afterSpike.mean - baseline.mean) < 0.001)
    #expect(afterSpike.robustSigma >= baseline.robustSigma)
  }

  @Test("Winsor clamp limits pull from moderate outlier")
  func winsorLimitsModerateOutlier() {
    var series: [Double] = []
    for i in 0..<20 {
      series.append(50.0 + Double(i % 2))
    }
    let baseline = BaselineTracker.ewmaBaseline(values: series)!
    #expect(baseline.robustSigma > 0.1)
    // 3.5σ: inside hard-reject (5σ), outside Winsor band (3σ) → clamped to 3σ.
    let outlier = baseline.mean + 3.5 * baseline.robustSigma
    let clampedEdge = baseline.mean + 3.0 * baseline.robustSigma
    let afterOutlier = baseline.updating(with: outlier)
    let afterClampedEdge = baseline.updating(with: clampedEdge)
    #expect(abs(afterOutlier.mean - afterClampedEdge.mean) < 0.001)
  }

  @Test("batch and incremental Winsor paths stay consistent")
  func batchMatchesIncremental() {
    var values = Array(repeating: 40.0, count: 15)
    values.append(80)
    values.append(contentsOf: Array(repeating: 40.0, count: 5))

    let batch = BaselineTracker.ewmaBaseline(values: values)!
    var incremental = ReadinessBaseline(mean: values[0], robustSigma: 0)
    for value in values.dropFirst() {
      incremental = incremental.updating(with: value)
    }
    #expect(abs(batch.mean - incremental.mean) < 0.001)
    #expect(abs(batch.robustSigma - incremental.robustSigma) < 0.001)
  }
}
