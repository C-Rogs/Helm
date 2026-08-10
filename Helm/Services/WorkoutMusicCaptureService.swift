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
    private let spotify: SpotifyAppRemoteService
    private var lastTitleArtistKey: String?
    private var pollTask: Task<Void, Never>?
    private var nowPlayingObserver: NSObjectProtocol?
    private var activeSessionID: String?
    /// Poll often enough to catch short sessions and track changes.
    private let pollIntervalSeconds: UInt64 = 5

    init(
        persistence: PersistenceStore,
        reader: any NowPlayingReading = MediaPlayerNowPlayingReader(),
        spotify: SpotifyAppRemoteService = .shared
    ) {
        self.persistence = persistence
        self.reader = reader
        self.spotify = spotify
        self.spotify.configure()
    }

    var prefersSpotifyCapture: Bool {
        spotify.isAuthorized
    }

    func sampleIfChanged(sessionID: String, now: Date = Date()) {
        guard !spotify.isConnected else { return }
        guard let snapshot = reader.currentSnapshot() else { return }
        insertSample(sessionID: sessionID, snapshot: snapshot, source: "nowPlaying", now: now)
    }

    func startPolling(sessionID: String) {
        stopPolling()
        activeSessionID = sessionID
        lastTitleArtistKey = nil

        if spotify.isAuthorized {
            spotify.connectForWorkout { [weak self] snapshot in
                guard let self, self.activeSessionID == sessionID else { return }
                self.insertSample(sessionID: sessionID, snapshot: snapshot, source: "spotify")
            }
        }

        // Always poll system Now Playing. App Remote wins while connected (`sampleIfChanged` skips).
        MPMusicPlayerController.systemMusicPlayer.beginGeneratingPlaybackNotifications()
        nowPlayingObserver = NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: MPMusicPlayerController.systemMusicPlayer,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.sampleIfChanged(sessionID: sessionID)
            }
        }

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
        if let nowPlayingObserver {
            NotificationCenter.default.removeObserver(nowPlayingObserver)
            self.nowPlayingObserver = nil
        }
        MPMusicPlayerController.systemMusicPlayer.endGeneratingPlaybackNotifications()
    }

    func reset() {
        stopPolling()
        spotify.disconnectWorkoutSession()
        activeSessionID = nil
        lastTitleArtistKey = nil
    }

    private func insertSample(
        sessionID: String,
        snapshot: NowPlayingSnapshot,
        source: String,
        now: Date = Date()
    ) {
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
            spotifyTrackID: snapshot.spotifyTrackID,
            bpm: snapshot.bpm,
            playbackRate: snapshot.playbackRate,
            source: source
        )
        try? persistence.workoutMusicSamples.insert(sample)
    }
}
