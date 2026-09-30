import Foundation
import Testing
@testable import HealthKitIngest

@Suite("Nutrition preferences store")
struct NutritionPreferencesStoreTests {
    @Test("photo CoFID grounding defaults off")
    func photoCofidGroundingDefaultOff() {
        let defaults = UserDefaults(suiteName: "com.cameronro.helm.tests.\(UUID().uuidString)")!
        let store = NutritionPreferencesStore(defaults: defaults)

        #expect(store.isPhotoCofidGroundingEnabled() == false)
    }

    @Test("photo CoFID grounding stays off")
    func photoCofidGroundingStaysOff() {
        let defaults = UserDefaults(suiteName: "com.cameronro.helm.tests.\(UUID().uuidString)")!
        let store = NutritionPreferencesStore(defaults: defaults)

        store.setPhotoCofidGroundingEnabled(true)
        #expect(store.isPhotoCofidGroundingEnabled() == false)

        store.setPhotoCofidGroundingEnabled(false)
        #expect(store.isPhotoCofidGroundingEnabled() == false)
    }
}
