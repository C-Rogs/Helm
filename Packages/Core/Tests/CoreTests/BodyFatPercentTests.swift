import Core
import Testing

@Suite("Body fat percent")
struct BodyFatPercentTests {
    @Test("fraction HealthKit values convert to stored percent")
    func fractionConverts() {
        #expect(BodyFatPercent.storedPercent(fromHealthKitPercentUnit: 0.145) == 14.5)
    }

    @Test("whole-number HealthKit values stay as stored percent")
    func wholePercentPassthrough() {
        #expect(BodyFatPercent.storedPercent(fromHealthKitPercentUnit: 14.5) == 14.5)
    }

    @Test("zero negative and over-cap values drop")
    func outOfRangeDrops() {
        #expect(BodyFatPercent.storedPercent(fromHealthKitPercentUnit: 0) == nil)
        #expect(BodyFatPercent.storedPercent(fromHealthKitPercentUnit: -0.1) == nil)
        #expect(BodyFatPercent.storedPercent(fromHealthKitPercentUnit: 70) == nil)
        #expect(BodyFatPercent.storedPercent(fromHealthKitPercentUnit: 0.7) == nil)
        #expect(BodyFatPercent.storedPercent(fromHealthKitPercentUnit: 244) == nil)
    }
}
