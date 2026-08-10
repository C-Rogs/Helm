import Core
import Foundation
import GRDB

struct WorkoutMusicSampleRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "workout_music_samples"

    var id: String
    var sessionID: String
    var sampledAt: String
    var title: String?
    var artist: String?
    var album: String?
    var genre: String?
    var spotifyTrackID: String?
    var bpm: Double?
    var playbackRate: Double?
    var source: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case sampledAt = "sampled_at"
        case title
        case artist
        case album
        case genre
        case spotifyTrackID = "spotify_track_id"
        case bpm
        case playbackRate = "playback_rate"
        case source
    }

    func toDomain() throws -> WorkoutMusicSample {
        WorkoutMusicSample(
            id: id,
            sessionID: sessionID,
            sampledAt: try ISO8601Coding.date(from: sampledAt),
            title: title,
            artist: artist,
            album: album,
            genre: genre,
            spotifyTrackID: spotifyTrackID,
            bpm: bpm,
            playbackRate: playbackRate,
            source: source
        )
    }

    static func from(_ sample: WorkoutMusicSample) -> WorkoutMusicSampleRecord {
        WorkoutMusicSampleRecord(
            id: sample.id,
            sessionID: sample.sessionID,
            sampledAt: ISO8601Coding.string(from: sample.sampledAt),
            title: sample.title,
            artist: sample.artist,
            album: sample.album,
            genre: sample.genre,
            spotifyTrackID: sample.spotifyTrackID,
            bpm: sample.bpm,
            playbackRate: sample.playbackRate,
            source: sample.source
        )
    }
}

public struct WorkoutMusicSampleRepository: Sendable {
    private let pool: DatabasePool

    public init(pool: DatabasePool) {
        self.pool = pool
    }

    public func insert(_ sample: WorkoutMusicSample) throws {
        try pool.write { db in
            try WorkoutMusicSampleRecord.from(sample).insert(db)
        }
    }

    public func list(sessionID: String) throws -> [WorkoutMusicSample] {
        try pool.read { db in
            try WorkoutMusicSampleRecord
                .filter(Column("session_id") == sessionID)
                .order(Column("sampled_at"))
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }
}
