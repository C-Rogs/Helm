import Core
import Foundation
import Testing
@testable import PlanKit

@Suite("RIR consistency")
struct RIRConsistencyTests {
    @Test("RPE 8 maps to RIR 2")
    func rpeToRIR() {
        #expect(PlanKit.rirFromRPE(8) == 2)
        #expect(PlanKit.rirFromRPE(10) == 0)
        #expect(PlanKit.rirFromRPE(6.5) == 3.5)
    }

    @Test("no history yields no flag")
    func noHistory() {
        let flag = PlanKit.rirConsistencyFlag(
            mass: Mass(kilograms: 100),
            reps: 5,
            claimedRIR: 4,
            historicalBestE1RM: nil
        )
        #expect(flag == nil)
    }

    @Test("overstated RIR vs e1RM history is flagged")
    func overstatedSpareCapacity() {
        // Historical best e1RM 100 kg. At 90 kg, Epley inverse predicts ~3.3 reps to failure.
        // Logging 5 reps @ RIR 3 claims 8 to failure → well above history.
        let flag = PlanKit.rirConsistencyFlag(
            mass: Mass(kilograms: 90),
            reps: 5,
            claimedRIR: 3,
            historicalBestE1RM: Mass(kilograms: 100)
        )
        #expect(flag == .overstatedSpareCapacity)
        #expect(flag?.message.contains("e1RM") == true)
    }

    @Test("plausible RIR vs history is not flagged")
    func plausibleRIR() {
        // Historical e1RM 100. At 80 kg predicts ~7.5 reps to failure.
        // 6 reps @ RIR 2 claims 8 → within +2 margin.
        let flag = PlanKit.rirConsistencyFlag(
            mass: Mass(kilograms: 80),
            reps: 6,
            claimedRIR: 2,
            historicalBestE1RM: Mass(kilograms: 100)
        )
        #expect(flag == nil)
    }

    @Test("exact e1RM set with high claimed RIR is flagged")
    func nearMaxWithSpareClaim() {
        // 100 kg x 1 with historical e1RM 100: predicted fail reps = 0.
        // Claiming RIR 3 is nonsense.
        let flag = PlanKit.rirConsistencyFlag(
            mass: Mass(kilograms: 100),
            reps: 1,
            claimedRIR: 3,
            historicalBestE1RM: Mass(kilograms: 100)
        )
        #expect(flag == .overstatedSpareCapacity)
    }
}
