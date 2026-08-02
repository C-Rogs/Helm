import AVFoundation
import Foundation
import OSLog

/// Plays the boxing-ring rest-end bell through headphones even when Silent switch is on.
@MainActor
final class RestTimerSoundPlayer {
    static let shared = RestTimerSoundPlayer()

    static let resourceName = "rest_bell"
    static let resourceExtension = "caf"

    private var player: AVAudioPlayer?
    private let logger = Logger(subsystem: "com.cameronro.helm", category: "Logger")

    func playRestBellIfEnabled(_ enabled: Bool) {
        guard enabled else { return }
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
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            self.player = player
            player.play()
        } catch {
            logger.error("Rest bell play failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
