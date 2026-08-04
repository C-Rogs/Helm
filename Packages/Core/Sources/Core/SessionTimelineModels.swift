import Foundation

/// One contiguous now-playing track span on the session timeline.
public struct SessionMusicSegment: Sendable, Hashable, Codable, Equatable, Identifiable {
    public var id: String { "\(startOffsetSeconds)-\(endOffsetSeconds)-\(title ?? "")-\(artist ?? "")" }
    public let startOffsetSeconds: Int
    public let endOffsetSeconds: Int
    public let title: String?
    public let artist: String?
    public let album: String?

    public init(
        startOffsetSeconds: Int,
        endOffsetSeconds: Int,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil
    ) {
        self.startOffsetSeconds = max(0, startOffsetSeconds)
        self.endOffsetSeconds = max(self.startOffsetSeconds, endOffsetSeconds)
        self.title = title
        self.artist = artist
        self.album = album
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
                album: sample.album
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
                    album: last.album
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

public enum SessionExerciseMarkerBuilder {
    public static let defaultShortNameMaxLength = 16

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
        return String(trimmed.prefix(maxLength - 1)) + "…"
    }
}
