import Foundation
import HealthKit
import Testing
@testable import HealthKitIngest

@Suite("HealthKit data presence")
struct HealthKitDataPresenceCheckerTests {
    @Test("reports data when samples exist for a type")
    func detectsPresence() async throws {
        let mockStore = MockHealthKitStoreClient()
        let loggedAt = Date()
        let sample = HKQuantitySample(
            type: HKQuantityType(.restingHeartRate),
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 58),
            start: loggedAt,
            end: loggedAt
        )
        mockStore.setSampleResults([sample], for: HKQuantityType(.restingHeartRate))

        let checker = HealthKitDataPresenceChecker(store: mockStore)
        let results = await checker.checkAllKinds()

        let resting = try #require(results.first(where: { $0.kind == .restingHeartRate }))
        #expect(resting.hasData)
        #expect(results.contains(where: { $0.kind == .sleep && !$0.hasData }))
    }

    @Test("reports no data when HealthKit is unavailable")
    func unavailableHealthData() async {
        let mockStore = MockHealthKitStoreClient()
        mockStore.setAvailable(false)

        let checker = HealthKitDataPresenceChecker(store: mockStore)
        let results = await checker.checkAllKinds()

        #expect(results.allSatisfy { !$0.hasData })
    }
}
