import Core
import Foundation

/// Exact Spotify-track tempo lookup through ReccoBeats' public audio-features endpoint.
///
/// App Remote exposes `spotify:track:<id>`, avoiding the title/artist ambiguity of
/// catalog search. The service needs no app key; tracks without a returned tempo fall
/// back to Deezer's name-based provider.
struct ReccoBeatsSongTempoProvider: SongTempoProviding {
    typealias DataLoader = @Sendable (URL) async throws -> Data

    private static let requestTimeout: TimeInterval = 8
    private let load: DataLoader

    init(load: DataLoader? = nil) {
        self.load = load ?? Self.defaultLoader
    }

    func tempo(for segment: SessionMusicSegment) async throws -> Double? {
        guard let spotifyTrackID = segment.spotifyTrackID else { return nil }
        var components = URLComponents(string: "https://api.reccobeats.com/v1/audio-features")
        components?.queryItems = [URLQueryItem(name: "ids", value: spotifyTrackID)]
        guard let url = components?.url else { return nil }

        let data = try await load(url)
        let response = try JSONDecoder().decode(ReccoBeatsAudioFeaturesResponse.self, from: data)
        return SongTempoMatching.validated(response.content.first?.tempo)
    }

    private static let defaultLoader: DataLoader = { url in
        var request = URLRequest(url: url)
        request.timeoutInterval = ReccoBeatsSongTempoProvider.requestTimeout
        request.setValue("Helm/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

private struct ReccoBeatsAudioFeaturesResponse: Decodable {
    let content: [ReccoBeatsAudioFeatures]
}

private struct ReccoBeatsAudioFeatures: Decodable {
    let tempo: Double?
}
