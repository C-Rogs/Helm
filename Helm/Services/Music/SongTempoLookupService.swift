import Core
import Diagnostics
import Foundation

/// Fills in song tempo the playback source could not provide.
///
/// Local library tracks carry a BPM tag, but Spotify App Remote and the Apple Music
/// catalog do not expose tempo, so those sessions need a name-based catalog lookup.
/// Lookup is opt-in; cached tempos are always applied because they already live on device.
@MainActor
final class SongTempoLookupService {
    static let shared = SongTempoLookupService()

    /// Ceiling per summary render so a long session cannot fan out dozens of requests.
    private static let maxLookupsPerRender = 8
    /// The summary sheet waits on this, so unresolved tracks fall back to spans rather
    /// than holding up the screen.
    private static let lookupBudgetSeconds = 4.0

    private let provider: any SongTempoProviding
    private let cache: SongTempoCache
    private let preferences: SongTempoPreferences
    private let logger = helmLogger(category: .ui)

    init(
        provider: any SongTempoProviding = DeezerSongTempoProvider(),
        cache: SongTempoCache = .shared,
        preferences: SongTempoPreferences = .shared
    ) {
        self.provider = provider
        self.cache = cache
        self.preferences = preferences
    }

    func fill(segments: [SessionMusicSegment]) async -> [SessionMusicSegment] {
        let queries = SessionMusicSegmentTempoFiller.missingTempoQueries(in: segments)
        guard !queries.isEmpty else { return segments }

        var resolved = cache.tempos(forKeys: queries.map(\.cacheKey))

        if preferences.lookupEnabled {
            let pending = queries.filter {
                resolved[$0.cacheKey] == nil && cache.shouldQuery(key: $0.cacheKey)
            }
            for outcome in await lookup(Array(pending.prefix(Self.maxLookupsPerRender))) {
                // A nil tempo is a real catalog answer, so it is cached as a miss.
                // Failures never reach here, keeping transient errors retryable.
                cache.store(key: outcome.key, tempo: outcome.tempo)
                if let tempo = outcome.tempo {
                    resolved[outcome.key] = tempo
                }
            }
        }

        return SessionMusicSegmentTempoFiller.apply(tempos: resolved, to: segments)
    }

    private func lookup(_ queries: [SongTempoQuery]) async -> [ResolvedTempo] {
        guard !queries.isEmpty else { return [] }
        let provider = self.provider
        let budget = Self.lookupBudgetSeconds

        return await withTaskGroup(of: LookupOutcome.self) { group in
            group.addTask {
                try? await Task.sleep(for: .seconds(budget))
                return .budgetExpired
            }
            for query in queries {
                group.addTask {
                    do {
                        let tempo = try await provider.tempo(for: query)
                        return .resolved(ResolvedTempo(key: query.cacheKey, tempo: tempo))
                    } catch {
                        return .failed(error.localizedDescription)
                    }
                }
            }

            var resolved: [ResolvedTempo] = []
            var remaining = queries.count
            while let outcome = await group.next() {
                switch outcome {
                case .budgetExpired:
                    group.cancelAll()
                    return resolved
                case .resolved(let tempo):
                    resolved.append(tempo)
                    remaining -= 1
                case .failed(let message):
                    logger.debug("Song tempo lookup failed: \(message, privacy: .public)")
                    remaining -= 1
                }
                if remaining == 0 {
                    group.cancelAll()
                    return resolved
                }
            }
            return resolved
        }
    }
}

private struct ResolvedTempo: Sendable {
    let key: String
    let tempo: Double?
}

private enum LookupOutcome: Sendable {
    case resolved(ResolvedTempo)
    case failed(String)
    case budgetExpired
}
