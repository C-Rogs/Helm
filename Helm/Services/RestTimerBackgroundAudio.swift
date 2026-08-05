import AVFoundation
import Foundation
import OSLog

/// Holds a mixable, silent playback loop for the duration of a rest timer.
///
/// iOS suspends the app a few seconds after it leaves the screen, which kills the in-app
/// rest bell. A notification alone is not enough: notification sound obeys the Silent switch,
/// so a phone on silent in the gym rings nothing. With `UIBackgroundModes: audio` and an
/// active `.playback` session, the process keeps running and the bell plays on time and
/// through Silent. `.mixWithOthers` keeps Spotify / Apple Music playing underneath.
@MainActor
final class RestTimerBackgroundAudio {
    static let shared = RestTimerBackgroundAudio()

    private static let sampleRate = 44_100.0
    private static let logger = Logger(subsystem: "com.cameronro.helm", category: "RestTimerKeepAlive")

    private var player: AVAudioPlayer?

    var isRunning: Bool {
        player?.isPlaying ?? false
    }

    init() {}

    func start() {
        guard !isRunning else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let loop: AVAudioPlayer
            if let player {
                loop = player
            } else {
                loop = try AVAudioPlayer(contentsOf: Self.silenceFileURL())
            }
            loop.numberOfLoops = -1
            loop.volume = 0
            guard loop.play() else {
                Self.logger.error("Rest keep-alive play() returned false")
                return
            }
            player = loop
        } catch {
            Self.logger.error("Rest keep-alive start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Leaves the session active: deactivating hands audio back abruptly and glitches music.
    func stop() {
        guard let player else { return }
        player.stop()
        player.currentTime = 0
    }

    /// One second of silence written to caches on first use, so no binary asset is bundled.
    private static func silenceFileURL() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent("helm-rest-keepalive.caf")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = buffer.frameCapacity
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
