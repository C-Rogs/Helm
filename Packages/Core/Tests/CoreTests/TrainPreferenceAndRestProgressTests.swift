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

    @Test("manual rest timer defaults off when unset")
    func manualRestTimerDefaultOff() {
        let suite = "helm.tests.trainPrefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(
            TrainPreferencePersistence.loadBool(
                key: TrainPreferencePersistence.manualRestTimerEnabledKey,
                defaults: defaults,
                defaultValue: false
            ) == false
        )
    }

    @Test("manual rest timer keeps legacy pawel key string")
    func manualRestTimerLegacyKeyString() {
        #expect(
            TrainPreferencePersistence.manualRestTimerEnabledKey
                == "helm.train.pawelModeEnabled"
        )
    }

    @Test("manual rest timer persists on via legacy key")
    func manualRestTimerPersistsOn() {
        let suite = "helm.tests.trainPrefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TrainPreferencePersistence.saveBool(
            true,
            key: TrainPreferencePersistence.manualRestTimerEnabledKey,
            defaults: defaults
        )
        #expect(
            TrainPreferencePersistence.loadBool(
                key: "helm.train.pawelModeEnabled",
                defaults: defaults,
                defaultValue: false
            ) == true
        )
    }

    @Test("manual rest duration defaults to ninety")
    func manualRestDurationDefault() {
        let suite = "helm.tests.trainPrefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(
            TrainPreferencePersistence.loadInt(
                key: TrainPreferencePersistence.manualRestTimerDurationSecondsKey,
                defaults: defaults,
                defaultValue: TrainPreferencePersistence.ManualRestTimerDuration.defaultSeconds
            ) == 90
        )
    }

    @Test("manual rest duration snaps and clamps")
    func manualRestDurationSnapClamp() {
        typealias Duration = TrainPreferencePersistence.ManualRestTimerDuration
        #expect(Duration.snapped(0) == 15)
        #expect(Duration.snapped(17) == 15)
        #expect(Duration.snapped(18) == 20)
        #expect(Duration.snapped(90) == 90)
        #expect(Duration.snapped(999) == 600)
        #expect(Duration.presets == [60, 90, 120, 180])
    }

    @Test("manual rest duration persists")
    func manualRestDurationPersists() {
        let suite = "helm.tests.trainPrefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        TrainPreferencePersistence.saveInt(
            135,
            key: TrainPreferencePersistence.manualRestTimerDurationSecondsKey,
            defaults: defaults
        )
        #expect(
            TrainPreferencePersistence.loadInt(
                key: TrainPreferencePersistence.manualRestTimerDurationSecondsKey,
                defaults: defaults,
                defaultValue: 90
            ) == 135
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
