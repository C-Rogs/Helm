import Core
import Foundation
import MediaPlayer
import Persistence

protocol NowPlayingReading: Sendable {
    func currentSnapshot() -> NowPlayingSnapshot?
}

struct MediaPlayerNowPlayingReader: NowPlayingReading {
    func currentSnapshot() -> NowPlayingSnapshot? {
        if let fromCenter = snapshot(from: MPNowPlayingInfoCenter.default().nowPlayingInfo) {
            return fromCenter
        }
        return snapshot(from: MPMusicPlayerController.systemMusicPlayer.nowPlayingItem)
    }

    private func snapshot(from info: [String: Any]?) -> NowPlayingSnapshot? {
        guard let info, !info.isEmpty else { return nil }

        let title = info[MPMediaItemPropertyTitle] as? String
        let artist = info[MPMediaItemPropertyArtist] as? String
        let album = info[MPMediaItemPropertyAlbumTitle] as? String
        let genre = info[MPMediaItemPropertyGenre] as? String
        let bpm = (info[MPMediaItemPropertyBeatsPerMinute] as? NSNumber)?.doubleValue
        let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double

        let snapshot = NowPlayingSnapshot(
            title: nonEmpty(title),
            artist: nonEmpty(artist),
            album: nonEmpty(album),
            genre: nonEmpty(genre),
            bpm: bpm.flatMap { $0 > 0 ? $0 : nil },
            playbackRate: rate
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    private func snapshot(from item: MPMediaItem?) -> NowPlayingSnapshot? {
        guard let item else { return nil }
        let snapshot = NowPlayingSnapshot(
            title: nonEmpty(item.title),
            artist: nonEmpty(item.artist),
            album: nonEmpty(item.albumTitle),
            genre: nonEmpty(item.genre),
            bpm: item.beatsPerMinute > 0 ? Double(item.beatsPerMinute) : nil,
            playbackRate: {
                let rate = MPMusicPlayerController.systemMusicPlayer.currentPlaybackRate
                return Double(rate)
            }()
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class WorkoutMusicCaptureService {
    private let reader: any NowPlayingReading
    private let persistence: PersistenceStore
    private var lastTitleArtistKey: String?
    private var pollTask: Task<Void, Never>?
    private let pollIntervalSeconds: UInt64 = 15

    init(
        persistence: PersistenceStore,
        reader: any NowPlayingReading = MediaPlayerNowPlayingReader()
    ) {
        self.persistence = persistence
        self.reader = reader
    }

    func sampleIfChanged(sessionID: String, now: Date = Date()) {
        guard let snapshot = reader.currentSnapshot() else { return }
        let key = "\(snapshot.title ?? "")|\(snapshot.artist ?? "")"
        guard key != lastTitleArtistKey else { return }
        lastTitleArtistKey = key

        let sample = WorkoutMusicSample(
            sessionID: sessionID,
            sampledAt: now,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            genre: snapshot.genre,
            bpm: snapshot.bpm,
            playbackRate: snapshot.playbackRate,
            source: "nowPlaying"
        )
        try? persistence.workoutMusicSamples.insert(sample)
    }

    func startPolling(sessionID: String) {
        stopPolling()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.sampleIfChanged(sessionID: sessionID)
                try? await Task.sleep(nanoseconds: self.pollIntervalSeconds * 1_000_000_000)
                guard !Task.isCancelled else { break }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func reset() {
        stopPolling()
        lastTitleArtistKey = nil
    }
}
