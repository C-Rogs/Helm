import AudioToolbox
import AVFoundation
import Core
import Foundation
import OSLog

/// Plays the rest-end alert (bundled caf or system sounds) at the chosen volume.
@MainActor
final class RestTimerSoundPlayer {
    static let shared = RestTimerSoundPlayer()

    static let resourceName = "rest_bell"
    static let resourceExtension = "caf"

    private var bellPlayer: AVAudioPlayer?
    private var sessionConfigured = false
    private let logger = Logger(subsystem: "com.cameronro.helm", category: "Logger")

    init() {
        loadBellPlayer()
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
        configureSessionIfNeeded()

        guard let player = bellPlayer else {
            logger.error("Rest bell missing from bundle (checked root and Sounds/)")
            playSystemSound(1_052)
            return
        }

        player.volume = volume
        player.currentTime = 0
        guard player.play() else {
            logger.error("Rest bell play() returned false")
            playSystemSound(1_052)
            return
        }
        scheduleSessionDeactivation(after: player.duration)
    }

    private func loadBellPlayer() {
        guard let url = Self.bundledBellURL() else {
            logger.error("Rest bell URL missing from bundle (checked root and Sounds/)")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            bellPlayer = player
        } catch {
            logger.error("Rest bell load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSessionDeactivation(after duration: TimeInterval) {
        let delay = max(duration, 0.5) + 0.25
        Task {
            try? await Task.sleep(for: .seconds(delay))
            deactivateSessionIfIdle()
        }
    }

    private func deactivateSessionIfIdle() {
        guard sessionConfigured else { return }
        guard bellPlayer?.isPlaying != true else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            sessionConfigured = false
        } catch {
            logger.error(
                "Rest timer audio session deactivate failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .defaultToSpeaker]
            )
            try session.setActive(true)
            sessionConfigured = true
        } catch {
            logger.error("Rest timer audio session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Bundle root (notifications + Copy Resources) or `Sounds/` folder reference.
    static func bundledBellURL() -> URL? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) {
            return url
        }
        if let url = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Sounds"
        ) {
            return url
        }
        return nil
    }

    private func playSystemSound(_ soundID: SystemSoundID) {
        configureSessionIfNeeded()
        AudioServicesPlaySystemSound(soundID)
    }
}
