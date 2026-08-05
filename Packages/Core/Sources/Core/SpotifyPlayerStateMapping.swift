import Foundation

/// Maps Spotify App Remote track fields into workout music samples.
public enum SpotifyPlayerStateMapping {
    public static func nowPlayingSnapshot(
        title: String?,
        artist: String?,
        album: String?
    ) -> NowPlayingSnapshot? {
        let snapshot = NowPlayingSnapshot(
            title: trimmedNonEmpty(title),
            artist: trimmedNonEmpty(artist),
            album: trimmedNonEmpty(album)
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    public static func workoutSample(
        sessionID: String,
        sampledAt: Date = Date(),
        title: String?,
        artist: String?,
        album: String?
    ) -> WorkoutMusicSample? {
        guard let snapshot = nowPlayingSnapshot(title: title, artist: artist, album: album) else {
            return nil
        }
        return WorkoutMusicSample(
            sessionID: sessionID,
            sampledAt: sampledAt,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            genre: snapshot.genre,
            bpm: snapshot.bpm,
            playbackRate: snapshot.playbackRate,
            source: "spotify"
        )
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
