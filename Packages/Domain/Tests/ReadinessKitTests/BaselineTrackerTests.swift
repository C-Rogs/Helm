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
}
