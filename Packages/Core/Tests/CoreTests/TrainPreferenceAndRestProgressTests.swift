import Foundation
import Testing
@testable import Core

@Suite("Train preference persistence")
struct TrainPreferencePersistenceTests {
    @Test("rest timer sound defaults on when unset")
    func restSoundDefaultOn() {
        let suite = "helm.tests.trainPrefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(
            TrainPreferencePersistence.loadBool(
                key: TrainPreferencePersistence.restTimerSoundEnabledKey,
                defaults: defaults,
                defaultValue: true
            ) == true
        )
    }

    @Test("rest timer sound persists off")
    func restSoundPersistsOff() {
        let suite = "helm.tests.trainPrefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TrainPreferencePersistence.saveBool(
            false,
            key: TrainPreferencePersistence.restTimerSoundEnabledKey,
            defaults: defaults
        )
        #expect(
            TrainPreferencePersistence.loadBool(
                key: TrainPreferencePersistence.restTimerSoundEnabledKey,
                defaults: defaults,
                defaultValue: true
            ) == false
        )
    }

    @Test("pawel mode defaults off when unset")
    func pawelModeDefaultOff() {
        let suite = "helm.tests.trainPrefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(
            TrainPreferencePersistence.loadBool(
                key: TrainPreferencePersistence.pawelModeEnabledKey,
                defaults: defaults,
                defaultValue: false
            ) == false
        )
    }

    @Test("pawel mode persists on")
    func pawelModePersistsOn() {
        let suite = "helm.tests.trainPrefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TrainPreferencePersistence.saveBool(
            true,
            key: TrainPreferencePersistence.pawelModeEnabledKey,
            defaults: defaults
        )
        #expect(
            TrainPreferencePersistence.loadBool(
                key: TrainPreferencePersistence.pawelModeEnabledKey,
                defaults: defaults,
                defaultValue: false
            ) == true
        )
    }
}

@Suite("Rest timer banner progress")
struct RestTimerBannerProgressTests {
    @Test("fraction empties as remaining drops")
    func emptiesWithRemaining() {
        #expect(RestTimerBannerProgress.remainingFraction(remainingSeconds: 90, totalSeconds: 90) == 1)
        #expect(RestTimerBannerProgress.remainingFraction(remainingSeconds: 45, totalSeconds: 90) == 0.5)
        #expect(RestTimerBannerProgress.remainingFraction(remainingSeconds: 0, totalSeconds: 90) == 0)
    }

    @Test("clamps out of range")
    func clamps() {
        #expect(RestTimerBannerProgress.remainingFraction(remainingSeconds: -5, totalSeconds: 60) == 0)
        #expect(RestTimerBannerProgress.remainingFraction(remainingSeconds: 120, totalSeconds: 60) == 1)
        #expect(RestTimerBannerProgress.remainingFraction(remainingSeconds: 10, totalSeconds: 0) == 1)
    }
}
