import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Prescription load bounds")
struct PrescriptionBoundsTests {
    @Test("coach-suggested increase respects max delta")
    func coachIncreaseCap() {
        #expect(PrescriptionBounds.isLoadWithinBounds(currentKg: 80, proposedKg: 88, intent: .coachSuggested))
        #expect(!PrescriptionBounds.isLoadWithinBounds(currentKg: 80, proposedKg: 88.1, intent: .coachSuggested))
    }

    @Test("user-directed increase is uncapped above")
    func userIncreaseUncapped() {
        #expect(PrescriptionBounds.isLoadWithinBounds(currentKg: 80, proposedKg: 100, intent: .userDirected))
    }

    @Test("decreases only floor at zero")
    func decreaseFloor() {
        #expect(PrescriptionBounds.isLoadWithinBounds(currentKg: 80, proposedKg: 20, intent: .coachSuggested))
        #expect(!PrescriptionBounds.isLoadWithinBounds(currentKg: 80, proposedKg: -1, intent: .userDirected))
        #expect(PrescriptionBounds.clampedLoadKg(-5) == 0)
    }

    @Test("disabled load safety allows large coach-suggested increases")
    func disabledLoadSafety() {
        #expect(
            PrescriptionBounds.isLoadWithinBounds(
                currentKg: 80,
                proposedKg: 100,
                intent: .coachSuggested,
                enforceCoachLoadCaps: false
            )
        )
        #expect(
            !PrescriptionBounds.isLoadWithinBounds(
                currentKg: 80,
                proposedKg: 100,
                intent: .coachSuggested,
                enforceCoachLoadCaps: true
            )
        )
    }
}
