import Testing
@testable import Core

@Suite("Heart rate zones")
struct HeartRateZoneTests {
    @Test("Edwards zone boundaries")
    func zoneBoundaries() {
        let resting = 60.0
        let max = 200.0
        #expect(HeartRateZone.zone(heartRateBPM: 100, restingHR: resting, maxHR: max) == .zone1)
        #expect(HeartRateZone.zone(heartRateBPM: 158, restingHR: resting, maxHR: max) == .zone2)
        #expect(HeartRateZone.zone(heartRateBPM: 200, restingHR: resting, maxHR: max) == .zone5)
    }
}
