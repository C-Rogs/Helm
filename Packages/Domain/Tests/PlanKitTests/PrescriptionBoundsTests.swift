import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("Prescription planning bounds")
struct PrescriptionBoundsTests {
    @Test("set clamp keeps engine allocations within the per-exercise cap")
    func setClamp() {
        #expect(PrescriptionBounds.clampSets(0) == PrescriptionBounds.minSetsPerExercise)
        #expect(PrescriptionBounds.clampSets(3) == 3)
        #expect(PrescriptionBounds.clampSets(9) == PrescriptionBounds.maxSetsPerExercise)
    }

    @Test("RPE clamp holds the loggable scale")
    func rpeClamp() {
        #expect(PrescriptionBounds.clampRPE(2) == PrescriptionBounds.minRPE)
        #expect(PrescriptionBounds.clampRPE(8) == 8)
        #expect(PrescriptionBounds.clampRPE(12) == PrescriptionBounds.maxRPE)
        #expect(PrescriptionBounds.clampRPE(9, cap: 7) == 7)
    }

    @Test("load floors at zero")
    func loadFloor() {
        #expect(PrescriptionBounds.clampedLoadKg(-5) == 0)
        #expect(PrescriptionBounds.clampedLoadKg(42.5) == 42.5)
    }
}
