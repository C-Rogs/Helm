import Core
import HealthKit

enum BodyFatQuantity {
    static func storedPercent(from quantity: HKQuantity) -> Double? {
        let percent = HKUnit.percent()
        guard quantity.is(compatibleWith: percent) else { return nil }
        return BodyFatPercent.storedPercent(fromHealthKitPercentUnit: quantity.doubleValue(for: percent))
    }
}
