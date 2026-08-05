import Foundation

/// Track identity for an external tempo lookup.
///
/// Playback sources differ in what they report: local library files carry a BPM tag,
/// while Spotify App Remote and the Apple Music catalog expose none. Tempo for those
/// tracks can only come from a name-based catalog lookup, so the query keeps the
/// cleaned title/artist pair plus the keys used for caching and match verification.
public struct SongTempoQuery: Sendable, Hashable {
    public let title: String
    public let artist: String?

    public init?(title: String?, artist: String?) {
        let cleanedTitle = SongTempoMatching.trimmed(title)
        guard !cleanedTitle.isEmpty else { return nil }
        let cleanedArtist = SongTempoMatching.trimmed(artist)
        self.title = cleanedTitle
        self.artist = cleanedArtist.isEmpty ? nil : cleanedArtist
    }

    public var cacheKey: String {
        SongTempoMatching.cacheKey(title: title, artist: artist)
    }

    /// Free-text search term. Catalog field syntax (`artist:"x" track:"y"`) misses more
    /// tracks than plain text, especially for punctuated artist names.
    public var searchTerm: String {
        guard let artist else { return title }
        return "\(artist) \(title)"
    }
}

/// Normalisation, cache keys, and match verification for name-based tempo lookups.
public enum SongTempoMatching {
    /// Tempo bounds for a plausible music track; anything outside is treated as missing.
    public static let minimumBPM = 40.0
    public static let maximumBPM = 220.0

    /// Parenthetical and suffix noise that names the same recording in a different edit.
    private static let versionKeywords = [
        "remaster", "remastered", "radio edit", "single version", "album version",
        "live", "mix", "remix", "edit", "version", "mono", "stereo", "bonus",
        "deluxe", "explicit", "clean", "feat", "featuring", "with"
    ]

    public static func validated(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= minimumBPM, value <= maximumBPM else {
            return nil
        }
        return value
    }

    public static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public static func cacheKey(title: String, artist: String?) -> String {
        "\(normalized(artist ?? ""))|\(normalized(title))"
    }

    /// Folds a title or artist to a comparable core: no diacritics, no bracketed edits,
    /// no version suffix, no punctuation.
    public static func normalized(_ value: String) -> String {
        var text = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        text = removeBracketedGroups(in: text)
        text = removeVersionSuffix(in: text)
        text = text.replacingOccurrences(
            of: "[^a-z0-9 ]",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.joined(separator: " ")
    }

    /// True when a catalog hit is the same recording as the query. Guards against search
    /// returning a cover, a different artist's remix, or an unrelated same-title track.
    public static func matches(
        candidateTitle: String?,
        candidateArtist: String?,
        query: SongTempoQuery
    ) -> Bool {
        let candidateTitleKey = normalized(trimmed(candidateTitle))
        let queryTitleKey = normalized(query.title)
        guard !candidateTitleKey.isEmpty, !queryTitleKey.isEmpty else { return false }
        guard candidateTitleKey == queryTitleKey else { return false }

        guard let queryArtist = query.artist else { return true }
        let candidateArtistKey = normalized(trimmed(candidateArtist))
        let queryArtistKey = normalized(queryArtist)
        guard !candidateArtistKey.isEmpty, !queryArtistKey.isEmpty else { return false }
        return candidateArtistKey == queryArtistKey
            || candidateArtistKey.contains(queryArtistKey)
            || queryArtistKey.contains(candidateArtistKey)
    }

    private static func removeBracketedGroups(in text: String) -> String {
        text.replacingOccurrences(
            of: "[\\(\\[\\{][^\\)\\]\\}]*[\\)\\]\\}]",
            with: " ",
            options: .regularExpression
        )
    }

    private static func removeVersionSuffix(in text: String) -> String {
        guard let separator = text.range(of: " - ", options: .backwards) else { return text }
        let suffix = text[separator.upperBound...].lowercased()
        guard versionKeywords.contains(where: suffix.contains) else { return text }
        return String(text[..<separator.lowerBound])
    }
}

/// Merges externally resolved tempo into session music segments.
public enum SessionMusicSegmentTempoFiller {
    /// Distinct tracks on the timeline that still need a tempo, in play order.
    public static func missingTempoQueries(in segments: [SessionMusicSegment]) -> [SongTempoQuery] {
        var seen: Set<String> = []
        var queries: [SongTempoQuery] = []
        for segment in segments where segment.bpm == nil {
            guard let query = SongTempoQuery(title: segment.title, artist: segment.artist) else {
                continue
            }
            guard seen.insert(query.cacheKey).inserted else { continue }
            queries.append(query)
        }
        return queries
    }

    /// Applies tempos keyed by `SongTempoQuery.cacheKey`. Captured tempo always wins.
    public static func apply(
        tempos: [String: Double],
        to segments: [SessionMusicSegment]
    ) -> [SessionMusicSegment] {
        guard !tempos.isEmpty else { return segments }
        return segments.map { segment in
            guard segment.bpm == nil,
                  let query = SongTempoQuery(title: segment.title, artist: segment.artist),
                  let tempo = SongTempoMatching.validated(tempos[query.cacheKey]) else {
                return segment
            }
            return SessionMusicSegment(
                startOffsetSeconds: segment.startOffsetSeconds,
                endOffsetSeconds: segment.endOffsetSeconds,
                title: segment.title,
                artist: segment.artist,
                album: segment.album,
                genre: segment.genre,
                bpm: tempo
            )
        }
    }
}
