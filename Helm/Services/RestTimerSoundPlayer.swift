import AudioToolbox
import AVFoundation
import Core
import Foundation
import OSLog

/// Plays the rest-end alert (bundled boxing bell or system sounds) at the chosen volume.
@MainActor
final class RestTimerSoundPlayer {
    static let shared = RestTimerSoundPlayer()

    static let bellResourceName = "boxing-bell"

    private var bellPlayer: AVAudioPlayer?
    private let logger = Logger(subsystem: "com.cameronro.helm", category: "Logger")

    init() {}

    /// Declares a mixable category at launch without activating the session or touching
    /// audio hardware. `AVAudioPlayer` init/`prepareToPlay` acquires hardware implicitly, and
    /// under the default solo-ambient category that pauses Spotify / Apple Music on open.
    func prewarmSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
        } catch {
            logger.error("Rest timer audio category failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func playRestBellIfEnabled(_ enabled: Bool) {
        guard enabled else { return }
        play(
            soundID: TrainPreferences.shared.restTimerSoundID,
            volume: TrainPreferences.shared.restTimerVolume
        )
    }

    func play(soundID: RestTimerSoundID, volume: RestTimerVolumeLevel) {
        guard volume.isEnabled else { return }
        // Backgrounded playback only works while the rest keep-alive session holds the app awake.
        guard AppLifecycleState.isForeground || RestTimerBackgroundAudio.shared.isRunning else { return }

        switch soundID {
        case .boxingBell:
            playBundledBell(volume: volume.playerVolume)
        case .chime:
            playSystemSound(1_007) // SMS tone (chime-like)
        case .beep:
            playSystemSound(1_113) // short beep
        }
    }

    private func playBundledBell(volume: Float) {
        configureSessionForPlayback()

        guard let player = loadedBellPlayer() else {
            logger.error("Boxing bell missing from bundle (checked mp3/caf in Sounds/)")
            playSystemSound(1_052)
            return
        }

        player.volume = volume
        player.currentTime = 0
        guard player.play() else {
            logger.error("Boxing bell play() returned false")
            playSystemSound(1_052)
            return
        }
    }

    /// Created on first play, never at launch: instantiating the player grabs audio hardware.
    private func loadedBellPlayer() -> AVAudioPlayer? {
        if let bellPlayer { return bellPlayer }
        guard let url = Self.bundledBellURL() else {
            logger.error("Boxing bell URL missing from bundle")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            bellPlayer = player
            return player
        } catch {
            logger.error("Boxing bell load failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func configureSessionForPlayback() {
        // Activate only when playing. Chat dictation may have switched to `.record`;
        // re-assert mixable playback here so the bell overlays music instead of stopping it.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            logger.error("Rest timer audio session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Prefer bundled mp3 (in-app); fall back to caf at bundle root or in Sounds/.
    static func bundledBellURL() -> URL? {
        let bundle = Bundle.main
        let candidates: [(String, String, String?)] = [
            (bellResourceName, "mp3", nil),
            (bellResourceName, "mp3", "Sounds"),
            (bellResourceName, "caf", nil),
            (bellResourceName, "caf", "Sounds")
        ]
        for (name, ext, subdirectory) in candidates {
            if let subdirectory,
               let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
            if subdirectory == nil,
               let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private func playSystemSound(_ soundID: SystemSoundID) {
        configureSessionForPlayback()
        AudioServicesPlaySystemSound(soundID)
    }
}
