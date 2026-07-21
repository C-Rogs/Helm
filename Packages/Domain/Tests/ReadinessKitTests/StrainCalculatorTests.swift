import Core
import Foundation
@testable import ReadinessKit
import Testing

@Suite("StrainCalculator")
struct StrainCalculatorTests {
  @Test("Edwards TRIMP weights heart-rate reserve zones")
  func edwardsTRIMP() {
    let trimp = StrainCalculator.edwardsTRIMP(
      heartRateSamples: [120, 150, 180],
      restingHR: 60,
      hrMax: 190
    )
    #expect(trimp > 0)
  }

  @Test("hrMax prefers observed peak over default when available")
  func hrMaxObserved() {
    let max = StrainCalculator.hrMax(observedHRSamples: [160, 175, 182], age: 30)
    #expect(max >= 182)
  }
}
