import Foundation
import Observation

/// On-device tempo memory so a track is looked up once, not once per summary view.
///
/// Misses are remembered too, with a retry window, because catalog coverage is partial
/// and re-querying every unknown track on every summary render would be wasteful.
@MainActor
@Observable
final class SongTempoCache {
    static let shared = SongTempoCache()

    static let tempoKey = "helm.songTempo.cache.tempos"
    static let missKey = "helm.songTempo.cache.misses"

    /// How long a known miss is trusted before the catalog is asked again.
    private static let missRetryInterval: TimeInterval = 14 * 24 * 60 * 60

    private let defaults: UserDefaults
    private var tempos: [String: Double]
    private var misses: [String: Date]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        tempos = defaults.dictionary(forKey: Self.tempoKey) as? [String: Double] ?? [:]
        misses = defaults.dictionary(forKey: Self.missKey) as? [String: Date] ?? [:]
    }

    var knownTempoCount: Int { tempos.count }

    func tempo(forKey key: String) -> Double? {
        tempos[key]
    }

    /// Cached tempos for the given keys, skipping anything not yet resolved.
    func tempos(forKeys keys: [String]) -> [String: Double] {
        var resolved: [String: Double] = [:]
        for key in keys {
            if let tempo = tempos[key] {
                resolved[key] = tempo
            }
        }
        return resolved
    }

    func shouldQuery(key: String, now: Date = Date()) -> Bool {
        if tempos[key] != nil { return false }
        guard let missedAt = misses[key] else { return true }
        return now.timeIntervalSince(missedAt) >= Self.missRetryInterval
    }

    func store(key: String, tempo: Double?, now: Date = Date()) {
        if let tempo {
            tempos[key] = tempo
            misses[key] = nil
        } else {
            misses[key] = now
        }
        persist()
    }

    func clear() {
        tempos = [:]
        misses = [:]
        persist()
    }

    private func persist() {
        defaults.set(tempos, forKey: Self.tempoKey)
        defaults.set(misses, forKey: Self.missKey)
    }
}
