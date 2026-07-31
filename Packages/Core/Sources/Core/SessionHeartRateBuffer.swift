import Foundation

/// One heart-rate sample captured during an active Train session.
public struct SessionHeartRateSample: Sendable, Hashable, Codable, Equatable, Identifiable {
    public var id: String { "\(offsetSeconds)-\(bpm)" }
    /// Seconds since session start.
    public let offsetSeconds: Int
    public let bpm: Int

    public init(offsetSeconds: Int, bpm: Int) {
        self.offsetSeconds = max(0, offsetSeconds)
        self.bpm = bpm
    }
}

/// Completed-set marker for overlay on the session HR chart.
public struct SessionSetMarker: Sendable, Hashable, Codable, Equatable, Identifiable {
    public var id: String { "\(offsetSeconds)-\(setNumber)" }
    public let offsetSeconds: Int
    public let setNumber: Int

    public init(offsetSeconds: Int, setNumber: Int) {
        self.offsetSeconds = max(0, offsetSeconds)
        self.setNumber = setNumber
    }
}

/// Accumulates live HR during a session, deduping near-duplicate samples.
public struct SessionHeartRateBuffer: Sendable, Equatable {
    public private(set) var samples: [SessionHeartRateSample]
    private let minIntervalSeconds: Int

    public init(samples: [SessionHeartRateSample] = [], minIntervalSeconds: Int = 5) {
        self.samples = samples
        self.minIntervalSeconds = max(1, minIntervalSeconds)
    }

    public mutating func record(bpm: Int, offsetSeconds: Int) {
        guard bpm > 0 else { return }
        let offset = max(0, offsetSeconds)
        if let last = samples.last {
            if offset - last.offsetSeconds < minIntervalSeconds, last.bpm == bpm {
                return
            }
            if offset < last.offsetSeconds {
                return
            }
        }
        samples.append(SessionHeartRateSample(offsetSeconds: offset, bpm: bpm))
    }

    public mutating func reset() {
        samples = []
    }
}

public enum SessionSetMarkerBuilder {
    /// Builds set markers from completed sets ordered by completion time.
    public static func markers(
        from session: WorkoutSessionDraft,
        startedAt: Date
    ) -> [SessionSetMarker] {
        var completed: [(Date, Int)] = []
        var setNumber = 0
        for exercise in session.exercises {
            for set in exercise.sets where set.status == .completed {
                setNumber += 1
                if let completedAt = set.completedAt {
                    completed.append((completedAt, setNumber))
                }
            }
        }
        return completed
            .sorted { $0.0 < $1.0 }
            .map { date, number in
                SessionSetMarker(
                    offsetSeconds: max(0, Int(date.timeIntervalSince(startedAt))),
                    setNumber: number
                )
            }
    }
}
