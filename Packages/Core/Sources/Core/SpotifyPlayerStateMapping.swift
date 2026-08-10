import Foundation

/// Maps Spotify App Remote track fields into workout music samples.
public enum SpotifyPlayerStateMapping {
    public static func nowPlayingSnapshot(
        title: String?,
        artist: String?,
        album: String?,
        spotifyURI: String? = nil
    ) -> NowPlayingSnapshot? {
        let snapshot = NowPlayingSnapshot(
            title: trimmedNonEmpty(title),
            artist: trimmedNonEmpty(artist),
            album: trimmedNonEmpty(album),
            spotifyTrackID: SpotifyTrackIdentifier.fromURI(spotifyURI)
        )
        return snapshot.isEmpty ? nil : snapshot
    }

    public static func workoutSample(
        sessionID: String,
        sampledAt: Date = Date(),
        title: String?,
        artist: String?,
        album: String?,
        spotifyURI: String? = nil
    ) -> WorkoutMusicSample? {
        guard let snapshot = nowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            spotifyURI: spotifyURI
        ) else {
            return nil
        }
        return WorkoutMusicSample(
            sessionID: sessionID,
            sampledAt: sampledAt,
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            genre: snapshot.genre,
            spotifyTrackID: snapshot.spotifyTrackID,
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

/// Normalises the identifier from a Spotify App Remote track URI.
public enum SpotifyTrackIdentifier {
    public static func fromURI(_ value: String?) -> String? {
        let prefix = "spotify:track:"
        guard let value, value.hasPrefix(prefix) else { return nil }
        let id = String(value.dropFirst(prefix.count))
        guard id.count == 22, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return id
    }
}
