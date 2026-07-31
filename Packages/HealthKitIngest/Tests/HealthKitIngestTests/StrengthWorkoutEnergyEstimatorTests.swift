import Foundation
import Testing
@testable import HealthKitIngest

@Suite("Strength workout energy estimator")
struct StrengthWorkoutEnergyEstimatorTests {
    @Test("energy scales with duration")
    func scalesWithDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let oneHour = StrengthWorkoutEnergyEstimator.activeEnergyKilocalories(
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            bodyMassKilograms: 75
        )
        let halfHour = StrengthWorkoutEnergyEstimator.activeEnergyKilocalories(
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            bodyMassKilograms: 75
        )
        #expect(oneHour == 6.0 * 75 * 1.0)
        #expect(halfHour == oneHour / 2)
    }

    @Test("zero duration yields zero energy")
    func zeroDuration() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(
            StrengthWorkoutEnergyEstimator.activeEnergyKilocalories(
                startedAt: start,
                endedAt: start
            ) == 0
        )
    }
}
