import Foundation
import Observation

/// Records whether the athlete opted into features that send data to a service.
/// Local HealthKit ingest, training, nutrition, and exports remain available either way.
@MainActor
@Observable
final class CloudFeatureConsentPreferences {
    static let shared = CloudFeatureConsentPreferences()

    private static let consentedKey = "helm.cloudFeatures.consented"
    private static let decidedKey = "helm.cloudFeatures.consentDecided"

    private let defaults: UserDefaults

    var isConsented: Bool {
        didSet {
            defaults.set(isConsented, forKey: Self.consentedKey)
            defaults.set(true, forKey: Self.decidedKey)
        }
    }

    var hasDecided: Bool {
        defaults.bool(forKey: Self.decidedKey)
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if !defaults.bool(forKey: Self.decidedKey),
           defaults.bool(forKey: OnboardingStore.completedDefaultsKey) {
            // Before this preference existed, completed onboarding implied that
            // cloud-backed Coach behavior was available. Preserve that behavior
            // for upgrades; new installs remain opt-in through onboarding.
            isConsented = true
            defaults.set(true, forKey: Self.consentedKey)
            defaults.set(true, forKey: Self.decidedKey)
        } else {
            isConsented = defaults.bool(forKey: Self.consentedKey)
        }
    }

    func accept() {
        isConsented = true
    }

    func decline() {
        isConsented = false
    }
}
