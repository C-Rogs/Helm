import Foundation

/// Recorded streaming chunks for contract tests without live network calls.
public enum FixtureStreamHarness: Sendable {
    public static func stream(chunks: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for chunk in chunks {
                    if Task.isCancelled {
                        continuation.finish(throwing: CoachProviderError.cancelled)
                        return
                    }
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    public static func loadChunks(named name: String, bundle: Bundle) throws -> [String] {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CoachProviderError.requestFailed("Missing fixture \(name).json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String].self, from: data)
    }

    public static func reassemble(_ stream: AsyncThrowingStream<String, Error>) async throws -> String {
        var parts: [String] = []
        for try await chunk in stream {
            parts.append(chunk)
        }
        return parts.joined()
    }
}
