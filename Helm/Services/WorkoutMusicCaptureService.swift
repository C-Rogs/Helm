import Core
import Foundation
import MediaPlayer
import Persistence

protocol NowPlayingReading: Sendable {
    func currentSnapshot() -> NowPlayingSnapshot?
}

struct MediaPlayerNowPlayingReader: NowPlayingReading {
    func currentSnapshot() -> NowPlayingSnapshot? {
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        guard let info, !info.isEmpty else { return nil }

        let title = info[MPMediaItemPropertyTitle] as? String
        let artist = info[MPMediaItemPropertyArtist] as? String
        let album = info[MPMediaItemPropertyAlbumTitle] as? String
        let genre = info[MPMediaItemPropertyGenre] as? String
        let bpm = (info[MPMediaItemPropertyBeatsPerMinute] as? NSNumber)?.doubleValue
        let rate = info[MPNowPlayingInfoPropertyPlaybackRate] as? Double

        let snapshot = NowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            bpm: bpm.flatMap { $0 > 0 ? $0 : nil },
            playbackRate: rate
        )
        return snapshot.isEmpty ? nil : snapshot
    }
}

@MainActor
final class WorkoutMusicCaptureService {
    private let reader: any NowPlayingReading
    private let persistence: PersistenceStore
    private var lastTitleArtistKey: String?

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

    func reset() {
        lastTitleArtistKey = nil
    }
}
