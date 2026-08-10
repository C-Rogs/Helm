import Foundation

/// One contiguous now-playing track span on the session timeline.
public struct SessionMusicSegment: Sendable, Hashable, Codable, Equatable, Identifiable {
    public var id: String { "\(startOffsetSeconds)-\(endOffsetSeconds)-\(title ?? "")-\(artist ?? "")" }
    public let startOffsetSeconds: Int
    public let endOffsetSeconds: Int
    public let title: String?
    public let artist: String?
    public let album: String?
    public let genre: String?
    /// Spotify track ID, when capture came from Spotify App Remote.
    public let spotifyTrackID: String?
    /// Track tempo when captured; nil when source omitted BPM or value was non-positive.
    public let bpm: Double?

    public init(
        startOffsetSeconds: Int,
        endOffsetSeconds: Int,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        genre: String? = nil,
        spotifyTrackID: String? = nil,
        bpm: Double? = nil
    ) {
        self.startOffsetSeconds = max(0, startOffsetSeconds)
        self.endOffsetSeconds = max(self.startOffsetSeconds, endOffsetSeconds)
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.spotifyTrackID = spotifyTrackID
        self.bpm = Self.validatedBPM(bpm)
    }

    public var durationSeconds: Int {
        max(0, endOffsetSeconds - startOffsetSeconds)
    }

    public var displayGenre: String? {
        let trimmed = genre?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        let artistTrimmed = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return artistTrimmed.isEmpty ? "Unknown track" : artistTrimmed
    }

    public var displayArtist: String? {
        let trimmed = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if trimmed == displayTitle { return nil }
        return trimmed
    }

    /// Rounded whole-number BPM for list/chart labels when present.
    public var displayBPM: Int? {
        guard let bpm else { return nil }
        return Int(bpm.rounded())
    }

    static func validatedBPM(_ value: Double?) -> Double? {
        guard let value, value > 0, value.isFinite else { return nil }
        return value
    }
}

/// First completed-set marker for each exercise on the session timeline.
public struct SessionExerciseMarker: Sendable, Hashable, Codable, Equatable, Identifiable {
    public var id: String { "\(offsetSeconds)-\(shortName)" }
    public let offsetSeconds: Int
    public let shortName: String

    public init(offsetSeconds: Int, shortName: String) {
        self.offsetSeconds = max(0, offsetSeconds)
        self.shortName = shortName
    }
}

public enum SessionMusicSegmentBuilder {
    public static func build(
        samples: [WorkoutMusicSample],
        startedAt: Date,
        endedAt: Date
    ) -> [SessionMusicSegment] {
        let sessionEndOffset = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        let sorted = samples.sorted { $0.sampledAt < $1.sampledAt }

        var segments: [SessionMusicSegment] = []
        for (index, sample) in sorted.enumerated() {
            guard !isEmptyTrack(title: sample.title, artist: sample.artist) else { continue }

            let startOffset = max(0, Int(sample.sampledAt.timeIntervalSince(startedAt)))
            let nextStart: Int? = sorted.dropFirst(index + 1).first.map {
                max(0, Int($0.sampledAt.timeIntervalSince(startedAt)))
            }
            let endOffset = nextStart ?? sessionEndOffset

            let segment = SessionMusicSegment(
                startOffsetSeconds: startOffset,
                endOffsetSeconds: endOffset,
                title: sample.title,
                artist: sample.artist,
                album: sample.album,
                genre: sample.genre,
                spotifyTrackID: sample.spotifyTrackID,
                bpm: sample.bpm
            )

            if let last = segments.last,
               last.title == segment.title,
               last.artist == segment.artist,
               last.endOffsetSeconds >= segment.startOffsetSeconds {
                segments[segments.count - 1] = SessionMusicSegment(
                    startOffsetSeconds: last.startOffsetSeconds,
                    endOffsetSeconds: max(last.endOffsetSeconds, segment.endOffsetSeconds),
                    title: last.title,
                    artist: last.artist,
                    album: last.album,
                    genre: last.genre ?? segment.genre,
                    spotifyTrackID: last.spotifyTrackID ?? segment.spotifyTrackID,
                    bpm: last.bpm ?? segment.bpm
                )
            } else {
                segments.append(segment)
            }
        }

        return segments
    }

    private static func isEmptyTrack(title: String?, artist: String?) -> Bool {
        let titleTrimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artistTrimmed = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return titleTrimmed.isEmpty && artistTrimmed.isEmpty
    }
}

/// One-line "what you listened to" blurb for the session timeline header.
public enum SessionMusicGenreSummary {
    public static let separator = " · "

    /// Top genres by total segment duration, capped at `limit`, joined with `separator`.
    public static func format(segments: [SessionMusicSegment], limit: Int = 3) -> String? {
        guard limit > 0 else { return nil }

        var totals: [String: Int] = [:]
        var displayNames: [String: String] = [:]
        var firstSeen: [String: Int] = [:]

        for (index, segment) in segments.enumerated() {
            guard let genre = segment.displayGenre, !isUnknown(genre) else { continue }
            let key = genre.lowercased()
            totals[key, default: 0] += segment.durationSeconds
            if displayNames[key] == nil {
                displayNames[key] = genre
                firstSeen[key] = index
            }
        }

        guard !totals.isEmpty else { return nil }

        let ordered = totals.keys.sorted { lhs, rhs in
            let lhsTotal = totals[lhs] ?? 0
            let rhsTotal = totals[rhs] ?? 0
            if lhsTotal != rhsTotal { return lhsTotal > rhsTotal }
            return (firstSeen[lhs] ?? 0) < (firstSeen[rhs] ?? 0)
        }

        let summary = ordered
            .prefix(limit)
            .compactMap { displayNames[$0] }
            .joined(separator: separator)

        return summary.isEmpty ? nil : summary
    }

    private static func isUnknown(_ genre: String) -> Bool {
        genre.lowercased() == "unknown"
    }
}

public enum SessionExerciseMarkerBuilder {
    public static let defaultShortNameMaxLength = 18

    /// Marks the first completed set of each exercise with a truncated friendly name.
    public static func markers(
        from session: WorkoutSessionDraft,
        startedAt: Date,
        displayNames: [String: String] = [:],
        shortNameMaxLength: Int = defaultShortNameMaxLength
    ) -> [SessionExerciseMarker] {
        var markers: [SessionExerciseMarker] = []

        for exercise in session.exercises.sorted(by: { $0.displayOrder < $1.displayOrder }) {
            let completedDates = exercise.sets
                .filter { $0.status == .completed }
                .map(\.completedAt)
                .compactMap { $0 }
            guard let firstCompleted = completedDates.min() else {
                continue
            }

            let friendly = ExerciseDisplayFormatter.friendlyName(
                for: exercise.exerciseID,
                displayNames: displayNames
            )
            let shortName = truncate(friendly, maxLength: shortNameMaxLength)
            let offset = max(0, Int(firstCompleted.timeIntervalSince(startedAt)))
            markers.append(SessionExerciseMarker(offsetSeconds: offset, shortName: shortName))
        }

        return markers.sorted { $0.offsetSeconds < $1.offsetSeconds }
    }

    public static func truncate(_ text: String, maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        guard maxLength > 1 else { return "…" }

        let available = maxLength - 1
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        var kept: [String] = []

        for word in words {
            let candidate = (kept + [word]).joined(separator: " ")
            guard candidate.count <= available else { break }
            kept.append(word)
        }

        if !kept.isEmpty {
            return kept.joined(separator: " ") + "…"
        }
        return String(trimmed.prefix(available)) + "…"
    }
}
