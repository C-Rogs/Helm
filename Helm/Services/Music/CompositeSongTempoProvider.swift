import Core

/// Uses Spotify's stable track identity first, then falls back to title/artist catalog search.
struct CompositeSongTempoProvider: SongTempoProviding {
    private let primary: any SongTempoProviding
    private let fallback: any SongTempoProviding

    init(
        primary: any SongTempoProviding = ReccoBeatsSongTempoProvider(),
        fallback: any SongTempoProviding = DeezerSongTempoProvider()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func tempo(for segment: SessionMusicSegment) async throws -> Double? {
        if let tempo = try await primary.tempo(for: segment) {
            return tempo
        }
        return try await fallback.tempo(for: segment)
    }
}
