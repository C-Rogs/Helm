import Foundation

public struct WorkoutMusicSample: Sendable, Hashable, Codable, Equatable {
    public let id: String
    public let sessionID: String
    public let sampledAt: Date
    public let title: String?
    public let artist: String?
    public let album: String?
    public let genre: String?
    public let bpm: Double?
    public let playbackRate: Double?
    public let source: String

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        sampledAt: Date = Date(),
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        bpm: Double? = nil,
        playbackRate: Double? = nil,
        source: String = "nowPlaying"
    ) {
        self.id = id
        self.sessionID = sessionID
        self.sampledAt = sampledAt
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.bpm = bpm
        self.playbackRate = playbackRate
        self.source = source
    }
}

/// Snapshot of system Now Playing for workout capture (no UI).
public struct NowPlayingSnapshot: Sendable, Hashable, Equatable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let genre: String?
    public let bpm: Double?
    public let playbackRate: Double?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        bpm: Double? = nil,
        playbackRate: Double? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.bpm = bpm
        self.playbackRate = playbackRate
    }

    public var isEmpty: Bool {
        title == nil && artist == nil && album == nil && genre == nil && bpm == nil
    }
}
