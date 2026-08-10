import Core
import Foundation

protocol SongTempoProviding: Sendable {
    func tempo(for segment: SessionMusicSegment) async throws -> Double?
}

/// Name-based tempo lookup against Deezer's public catalog.
///
/// Chosen because it needs no API key, no account, and no OAuth: Spotify removed
/// `/audio-features` in November 2024 with no replacement, and the Apple Music catalog
/// exposes no tempo field at all. Coverage is partial, so a nil result is normal.
struct DeezerSongTempoProvider: SongTempoProviding {
    typealias DataLoader = @Sendable (URL) async throws -> Data

    /// Search hits lead with the most popular recording; a few candidates are enough to
    /// find one that both matches the query and carries a tempo.
    private static let candidateLimit = 5
    private static let requestTimeout: TimeInterval = 8

    private let load: DataLoader

    init(load: DataLoader? = nil) {
        self.load = load ?? Self.defaultLoader
    }

    func tempo(for segment: SessionMusicSegment) async throws -> Double? {
        guard let query = SongTempoQuery(title: segment.title, artist: segment.artist) else { return nil }
        let candidates = try await search(query)
        for candidate in candidates {
            guard SongTempoMatching.matches(
                candidateTitle: candidate.title,
                candidateArtist: candidate.artist?.name,
                query: query
            ) else { continue }

            if let tempo = try await tempo(trackID: candidate.id) {
                return tempo
            }
        }
        return nil
    }

    private func search(_ query: SongTempoQuery) async throws -> [DeezerTrack] {
        var components = URLComponents(string: "https://api.deezer.com/search/track")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query.searchTerm),
            URLQueryItem(name: "limit", value: String(Self.candidateLimit))
        ]
        guard let url = components?.url else { return [] }
        let data = try await load(url)
        return try JSONDecoder().decode(DeezerSearchResponse.self, from: data).data
    }

    private func tempo(trackID: Int) async throws -> Double? {
        guard let url = URL(string: "https://api.deezer.com/track/\(trackID)") else { return nil }
        let data = try await load(url)
        let track = try JSONDecoder().decode(DeezerTrack.self, from: data)
        return SongTempoMatching.validated(track.bpm)
    }

    private static let defaultLoader: DataLoader = { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = DeezerSongTempoProvider.requestTimeout
        request.setValue("Helm/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private struct DeezerSearchResponse: Decodable {
    let data: [DeezerTrack]
}

private struct DeezerTrack: Decodable {
    struct Artist: Decodable {
        let name: String?
    }

    let id: Int
    let title: String?
    let artist: Artist?
    /// Present on the track resource only, and zero when Deezer has not analysed the track.
    let bpm: Double?
}
