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

    private var player: AVAudioPlayer?
    private let logger = Logger(subsystem: "com.cameronro.helm", category: "Logger")

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
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            logger.error("Rest timer audio session failed: \(error.localizedDescription, privacy: .public)")
        }

        guard let url = Bundle.main.url(
            forResource: Self.resourceName,
            withExtension: Self.resourceExtension
        ) else {
            logger.error("Rest bell sound missing from bundle")
            AudioServicesPlaySystemSound(1_007)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            self.player = player
            player.play()
        } catch {
            logger.error("Rest bell play failed: \(error.localizedDescription, privacy: .public)")
            AudioServicesPlaySystemSound(1_007)
        }
    }

    private func playSystemSound(_ soundID: SystemSoundID) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            logger.error("Rest timer audio session failed: \(error.localizedDescription, privacy: .public)")
        }
        AudioServicesPlaySystemSound(soundID)
    }
}
